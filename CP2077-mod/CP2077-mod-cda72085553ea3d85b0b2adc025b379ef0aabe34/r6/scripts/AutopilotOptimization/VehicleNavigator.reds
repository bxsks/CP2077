// VehicleNavigator.reds
// 自动驾驶优化 Mod
// Autopilot Optimization Mod – Navigation and waypoint path following

module AutopilotOptimization
import AutopilotOptimization.*

// ─────────────────────────────────────────────────────────────────────────────
// Waypoint record – a single point along the computed route
// ─────────────────────────────────────────────────────────────────────────────

public struct Waypoint {
    public let position: Vector4;
    public let isLaneChange: Bool;   // true = lateral lane-change point
    public let speedLimitKph: Float; // 0 = use global config limit
}

// ─────────────────────────────────────────────────────────────────────────────
// VehicleNavigator – waypoint management & steering output
// ─────────────────────────────────────────────────────────────────────────────

public class VehicleNavigator {

    private let m_vehicle: wref<VehicleObject>;

    private let m_waypoints: array<Waypoint>;
    private let m_waypointIndex: Int32;

    private let m_destination: Vector4;
    private let m_hasDestination: Bool;

    // Current smoothed steering value in [-1, 1].
    private let m_currentSteer: Float;

    // ── Construction ──────────────────────────────────────────────────────────

    public static func Create(vehicle: ref<VehicleObject>) -> ref<VehicleNavigator> {
        let nav = new VehicleNavigator();
        nav.m_vehicle        = vehicle;
        nav.m_waypointIndex  = 0;
        nav.m_hasDestination = false;
        nav.m_currentSteer   = 0.0;
        return nav;
    }

    // ── Destination / route management ───────────────────────────────────────

    /// Set a new destination and rebuild the waypoint list.
    public func SetDestination(dest: Vector4) -> Void {
        m_destination    = dest;
        m_hasDestination = true;
        m_waypointIndex  = 0;
        this.BuildWaypointRoute(dest);
        LogChannel(AutopilotConfig.LogChannel(),
            s"Navigator: route built – \(ArraySize(m_waypoints)) waypoints");
    }

    /// Clear the active route without engaging or disengaging autopilot.
    public func CancelNavigation() -> Void {
        ArrayClear(m_waypoints);
        m_waypointIndex  = 0;
        m_hasDestination = false;
        m_currentSteer   = 0.0;
    }

    // ── Waypoint traversal ────────────────────────────────────────────────────

    /// Straight-line distance from the vehicle to the currently-tracked waypoint.
    public func DistanceToNextWaypoint() -> Float {
        if !m_hasDestination || ArraySize(m_waypoints) == 0 { return 0.0; }
        if !IsDefined(m_vehicle) { return 0.0; }

        let wp: Waypoint = m_waypoints[m_waypointIndex];
        let vPos: Vector4 = m_vehicle.GetWorldPosition();
        return VectorDistance(vPos, wp.position);
    }

    /// Advance to the next waypoint in the list.
    /// Returns true if there are more waypoints to follow, false if the route
    /// is exhausted.
    public func AdvanceToNextWaypoint() -> Bool {
        m_waypointIndex += 1;
        if m_waypointIndex >= ArraySize(m_waypoints) {
            m_waypointIndex = ArraySize(m_waypoints) - 1;
            return false;
        }
        LogChannel(AutopilotConfig.LogChannel(),
            s"Navigator: advancing to waypoint \(m_waypointIndex)");
        return true;
    }

    /// Effective speed limit at the current waypoint (km/h).
    public func CurrentWaypointSpeedLimit() -> Float {
        if ArraySize(m_waypoints) == 0 { return AutopilotConfig.MaxCruiseSpeedKph(); }
        let limit: Float = m_waypoints[m_waypointIndex].speedLimitKph;
        return limit > 0.0 ? limit : AutopilotConfig.MaxCruiseSpeedKph();
    }

    // ── Steering output ───────────────────────────────────────────────────────

    /// Compute smooth steering toward the active waypoint and apply it.
    public func ApplySteeringToWaypoint() -> Void {
        if !IsDefined(m_vehicle) { return; }
        if ArraySize(m_waypoints) == 0 { return; }

        let targetWp: Waypoint = m_waypoints[m_waypointIndex];
        let rawSteer: Float    = this.ComputeSteer(targetWp.position);
        let smoothed: Float    = this.SmoothSteer(rawSteer);

        m_currentSteer = smoothed;
        m_vehicle.SetSteering(smoothed);

        if AutopilotConfig.VerboseLogging() {
            LogChannel(AutopilotConfig.LogChannel(),
                s"Navigator: steer=\(smoothed)");
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /// Build a simplified straight-line route subdivided into segments.
    /// In a production mod this would query the game's traffic / road graph.
    private func BuildWaypointRoute(dest: Vector4) -> Void {
        ArrayClear(m_waypoints);
        if !IsDefined(m_vehicle) { return; }

        let start: Vector4 = m_vehicle.GetWorldPosition();
        let totalDist: Float = VectorDistance(start, dest);

        // Subdivide into ~20 m segments so the controller has intermediate
        // progress checkpoints.  For short routes (≤ 20 m) we skip intermediate
        // waypoints entirely – only the final waypoint is needed.
        let segmentLen: Float = 20.0;
        let numSegments: Int32 = MaxI(Cast<Int32>(totalDist / segmentLen) - 1, 0);

        let i: Int32 = 1;
        while i <= numSegments {
            let t: Float = Cast<Float>(i) / Cast<Float>(numSegments + 1);
            let wp: Waypoint;
            wp.position = VectorInterpolate(start, dest, t);
            wp.isLaneChange   = false;
            wp.speedLimitKph  = 0.0;
            ArrayPush(m_waypoints, wp);
            i += 1;
        }

        // Always append the exact destination as the final waypoint.
        let finalWp: Waypoint;
        finalWp.position      = dest;
        finalWp.isLaneChange  = false;
        finalWp.speedLimitKph = AutopilotConfig.ApproachSpeedKph();
        ArrayPush(m_waypoints, finalWp);
    }

    /// Calculate the raw desired steering value in [-1, 1] using the
    /// heading error between the vehicle's forward vector and the
    /// vector toward the target waypoint.
    private func ComputeSteer(targetPos: Vector4) -> Float {
        if !IsDefined(m_vehicle) { return 0.0; }

        let vPos: Vector4    = m_vehicle.GetWorldPosition();
        let forward: Vector4 = m_vehicle.GetWorldForward();

        // Vector from vehicle to target (ignore Z for 2-D heading error).
        let toTarget: Vector4 = targetPos - vPos;
        let toTargetNorm: Vector4 = VectorNormalize2D(toTarget);
        let forwardNorm: Vector4  = VectorNormalize2D(forward);

        // Cross-product Z component gives signed lateral error.
        let cross: Float = forwardNorm.X * toTargetNorm.Y
                         - forwardNorm.Y * toTargetNorm.X;

        // Clamp to [-1, 1] steering range.
        return ClampF(cross * 2.0, -1.0, 1.0);
    }

    /// Exponential smoothing of the steering signal to prevent jerky inputs.
    private func SmoothSteer(rawSteer: Float) -> Float {
        let alpha: Float = AutopilotConfig.SteeringSmoothFactor();
        let smoothed: Float = m_currentSteer + alpha * (rawSteer - m_currentSteer);

        // Cap per-tick delta to MaxSteerDeltaDeg converted to a normalised value.
        // Division by 45 maps degrees to the [-1, 1] normalised steering range,
        // where ±1 represents the vehicle's maximum physical steering lock
        // (assumed to be 45° in the base game vehicle physics model).
        let maxDelta: Float = AutopilotConfig.MaxSteerDeltaDeg() / 45.0;
        let delta: Float    = smoothed - m_currentSteer;
        if AbsF(delta) > maxDelta {
            return m_currentSteer + (delta > 0.0 ? maxDelta : -maxDelta);
        }
        return smoothed;
    }

    // ── Math utilities ────────────────────────────────────────────────────────

    private func VectorDistance(a: Vector4, b: Vector4) -> Float {
        let dx: Float = b.X - a.X;
        let dy: Float = b.Y - a.Y;
        let dz: Float = b.Z - a.Z;
        return SqrtF(dx * dx + dy * dy + dz * dz);
    }

    private func VectorInterpolate(a: Vector4, b: Vector4, t: Float) -> Vector4 {
        let result: Vector4;
        result.X = a.X + (b.X - a.X) * t;
        result.Y = a.Y + (b.Y - a.Y) * t;
        result.Z = a.Z + (b.Z - a.Z) * t;
        result.W = 1.0;
        return result;
    }

    private func VectorNormalize2D(v: Vector4) -> Vector4 {
        let len: Float = SqrtF(v.X * v.X + v.Y * v.Y);
        let result: Vector4;
        if len > 0.0001 {
            result.X = v.X / len;
            result.Y = v.Y / len;
        }
        result.Z = 0.0;
        result.W = 0.0;
        return result;
    }
}
