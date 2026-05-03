// TrafficOptimizer.reds
// 自动驾驶优化 Mod
// Autopilot Optimization Mod – Traffic awareness and adaptive speed control

module AutopilotOptimization
import AutopilotOptimization.*

// ─────────────────────────────────────────────────────────────────────────────
// Traffic light state
// ─────────────────────────────────────────────────────────────────────────────

public enum TrafficLightPhase {
    Unknown = 0,
    Green   = 1,
    Yellow  = 2,
    Red     = 3
}

// ─────────────────────────────────────────────────────────────────────────────
// TrafficOptimizer
// ─────────────────────────────────────────────────────────────────────────────

public class TrafficOptimizer {

    private let m_vehicle: wref<VehicleObject>;

    // Obstacle detection
    private let m_obstacleDetected: Bool;
    private let m_obstacleDistance: Float;

    // Traffic-light state
    private let m_lightPhase: TrafficLightPhase;
    private let m_lightDistance: Float;
    private let m_greenHoldTimer: Float;  // countdown before accelerating on green

    // Avoidance
    private let m_avoidanceOffset: Float; // signed lateral offset currently applied

    // ── Construction ──────────────────────────────────────────────────────────

    public static func Create(vehicle: ref<VehicleObject>) -> ref<TrafficOptimizer> {
        let opt = new TrafficOptimizer();
        opt.m_vehicle           = vehicle;
        opt.m_obstacleDetected  = false;
        opt.m_obstacleDistance  = 9999.0;
        opt.m_lightPhase        = TrafficLightPhase.Unknown;
        opt.m_lightDistance     = 9999.0;
        opt.m_greenHoldTimer    = 0.0;
        opt.m_avoidanceOffset   = 0.0;
        return opt;
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Returns true when the forward path is blocked (vehicle, obstacle, or
    /// a red/yellow traffic light within detection range).
    public func IsObstacleAhead() -> Bool {
        this.ScanForObstacles();
        this.ScanTrafficLights();
        return m_obstacleDetected
            || Equals(m_lightPhase, TrafficLightPhase.Red)
            || Equals(m_lightPhase, TrafficLightPhase.Yellow);
    }

    /// Return the recommended cruise speed given current traffic conditions.
    /// `maxKph` is the caller's desired ceiling; this method may only reduce it.
    public func GetRecommendedSpeed(maxKph: Float) -> Float {
        let speed: Float = maxKph;

        // Slow down when approaching a traffic light within detection range.
        if m_lightDistance < AutopilotConfig.TrafficLightDetectionRangeM() {
            if Equals(m_lightPhase, TrafficLightPhase.Green) {
                // We're clear – apply no penalty but honour the green-light hold.
                if m_greenHoldTimer > 0.0 {
                    speed = AutopilotConfig.ApproachSpeedKph();
                }
            } else {
                // Yellow or red – creep or stop.
                speed = MinF(speed, AutopilotConfig.ApproachSpeedKph());
            }
        }

        // Reduce speed proportionally to distance from the vehicle ahead.
        if m_obstacleDetected {
            let safeGap: Float   = AutopilotConfig.MinFollowDistanceM();
            let gapRatio: Float  = m_obstacleDistance / safeGap;
            if gapRatio < 2.0 {
                speed = MinF(speed, AutopilotConfig.UrbanSpeedCapKph() * (gapRatio / 2.0));
            }
        }

        return MaxF(speed, 0.0);
    }

    /// Perform one tick of lateral avoidance while an obstacle is present.
    public func ApplyAvoidanceManoeuvre(dt: Float) -> Void {
        if !IsDefined(m_vehicle) { return; }

        // Lerp toward the target lateral offset to avoid the obstacle.
        let targetOffset: Float = AutopilotConfig.ObstacleAvoidanceOffsetM();
        m_avoidanceOffset = m_avoidanceOffset
                          + (targetOffset - m_avoidanceOffset)
                          * AutopilotConfig.AvoidanceOffsetSmoothFactor();

        // Express the lateral offset as a steering bias.
        let steerBias: Float = ClampF(
            m_avoidanceOffset / AutopilotConfig.AvoidanceSteeringDivisor(),
            -1.0, 1.0);
        m_vehicle.SetSteering(steerBias);

        // Slow down during avoidance.
        m_vehicle.SetThrottle(AutopilotConfig.AvoidanceThrottleFactor());

        if AutopilotConfig.VerboseLogging() {
            LogChannel(AutopilotConfig.LogChannel(),
                s"Avoidance: offset=\(m_avoidanceOffset), steer=\(steerBias)");
        }
    }

    /// Update the green-light hold timer.  Call once per frame.
    public func TickTimers(dt: Float) -> Void {
        if m_greenHoldTimer > 0.0 { m_greenHoldTimer -= dt; }
    }

    // ── Private scan helpers ──────────────────────────────────────────────────

    /// Update obstacle state by performing a forward ray cast.
    /// In a production mod this would use the game's QueryFilter / SweepSphere
    /// API; here we delegate to a virtual game query so the logic is clear.
    private func ScanForObstacles() -> Void {
        if !IsDefined(m_vehicle) { return; }

        let origin: Vector4  = m_vehicle.GetWorldPosition();
        let forward: Vector4 = m_vehicle.GetWorldForward();
        let range: Float     = AutopilotConfig.ObstacleLookaheadM();

        // Ask the game world for the nearest dynamic entity in front.
        let hitDist: Float = m_vehicle.RayCastForwardDistance(range);

        if hitDist > 0.0 && hitDist < range {
            m_obstacleDetected = true;
            m_obstacleDistance = hitDist;
        } else {
            m_obstacleDetected = false;
            m_obstacleDistance = range;
            // Begin relaxing the avoidance offset back to centre.
            if m_avoidanceOffset != 0.0 {
                m_avoidanceOffset *= AutopilotConfig.AvoidanceOffsetDecayRate();
                if AbsF(m_avoidanceOffset) < AutopilotConfig.AvoidanceOffsetDeadbandM() {
                    m_avoidanceOffset = 0.0;
                }
            }
        }
    }

    /// Detect the nearest traffic light in front and update light phase.
    private func ScanTrafficLights() -> Void {
        if !IsDefined(m_vehicle) { return; }

        let range: Float = AutopilotConfig.TrafficLightDetectionRangeM();
        let prevPhase: TrafficLightPhase = m_lightPhase;

        let lightInfo: TrafficLightQueryResult =
            m_vehicle.QueryNearestTrafficLight(range);

        m_lightDistance = lightInfo.distance;
        m_lightPhase    = this.MapLightState(lightInfo.state);

        // When a light just turned green, insert a brief hold before flooring it.
        if Equals(prevPhase, TrafficLightPhase.Red)
            && Equals(m_lightPhase, TrafficLightPhase.Green) {
            m_greenHoldTimer = AutopilotConfig.GreenLightHoldS();
        }
    }

    private func MapLightState(state: ETrafficLightColor) -> TrafficLightPhase {
        switch state {
            case ETrafficLightColor.Green:  return TrafficLightPhase.Green;
            case ETrafficLightColor.Yellow: return TrafficLightPhase.Yellow;
            case ETrafficLightColor.Red:    return TrafficLightPhase.Red;
            default:                        return TrafficLightPhase.Unknown;
        }
    }
}
