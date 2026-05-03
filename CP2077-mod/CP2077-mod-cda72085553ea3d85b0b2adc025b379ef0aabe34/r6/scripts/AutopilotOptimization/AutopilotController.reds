// AutopilotController.reds
// 自动驾驶优化 Mod – 核心状态机与控制器
// Autopilot Optimization Mod – Core state machine and controller

module AutopilotOptimization
import AutopilotOptimization.*

// ─────────────────────────────────────────────────────────────────────────────
// Autopilot state enumeration
// ─────────────────────────────────────────────────────────────────────────────

public enum AutopilotState {
    Inactive    = 0,  // Autopilot is off; player drives manually
    Engaging    = 1,  // Transitioning from manual to autopilot (smooth hand-off)
    Cruising    = 2,  // Steady-state autopilot cruise along current route
    Approaching = 3,  // Nearing the active waypoint; decelerating
    Avoiding    = 4,  // Active obstacle or traffic-light avoidance manoeuvre
    Paused      = 5,  // Temporarily suspended after a manual override
    Arrived     = 6   // Reached the destination waypoint
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistent controller class – one instance per possessed vehicle
// ─────────────────────────────────────────────────────────────────────────────

public class AutopilotController {

    private let m_vehicle: wref<VehicleObject>;
    private let m_navigator: ref<VehicleNavigator>;
    private let m_trafficOpt: ref<TrafficOptimizer>;

    private let m_state: AutopilotState;
    private let m_pauseTimer: Float;    // counts down to auto-resume
    private let m_arrivalRadius: Float; // metres – treated as "arrived"

    // ── Construction ──────────────────────────────────────────────────────────

    public static func Create(vehicle: ref<VehicleObject>) -> ref<AutopilotController> {
        let ctrl = new AutopilotController();
        ctrl.m_vehicle      = vehicle;
        ctrl.m_navigator    = VehicleNavigator.Create(vehicle);
        ctrl.m_trafficOpt   = TrafficOptimizer.Create(vehicle);
        ctrl.m_state        = AutopilotState.Inactive;
        ctrl.m_pauseTimer   = 0.0;
        ctrl.m_arrivalRadius = 5.0;
        return ctrl;
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Engage autopilot and drive to the supplied world position.
    public func Engage(destination: Vector4) -> Void {
        if !IsDefined(m_vehicle) {
            LogChannel(AutopilotConfig.LogChannel(),
                       "AutopilotController.Engage: no vehicle bound");
            return;
        }
        m_navigator.SetDestination(destination);
        this.TransitionTo(AutopilotState.Engaging);
        LogChannel(AutopilotConfig.LogChannel(), "Autopilot ENGAGED");
    }

    /// Disengage autopilot immediately (player took over or explicit request).
    public func Disengage() -> Void {
        m_navigator.CancelNavigation();
        this.TransitionTo(AutopilotState.Inactive);
        LogChannel(AutopilotConfig.LogChannel(), "Autopilot DISENGAGED");
    }

    /// Notify the controller that the player touched the controls.
    public func NotifyManualOverride() -> Void {
        if Equals(m_state, AutopilotState.Inactive) { return; }
        m_pauseTimer = AutopilotConfig.AutoResumeDelayS();
        this.TransitionTo(AutopilotState.Paused);
        LogChannel(AutopilotConfig.LogChannel(), "Autopilot PAUSED – manual override");
    }

    /// Returns the current autopilot state.
    public func GetState() -> AutopilotState { return m_state; }

    /// Returns true when the autopilot is actively controlling the vehicle.
    public func IsActive() -> Bool {
        return !Equals(m_state, AutopilotState.Inactive)
            && !Equals(m_state, AutopilotState.Paused)
            && !Equals(m_state, AutopilotState.Arrived);
    }

    // ── Per-frame update (called from AutopilotHooks.reds) ────────────────────

    public func OnTick(deltaTime: Float) -> Void {
        switch m_state {
            case AutopilotState.Engaging:
                this.TickEngaging(deltaTime);
                break;
            case AutopilotState.Cruising:
                this.TickCruising(deltaTime);
                break;
            case AutopilotState.Approaching:
                this.TickApproaching(deltaTime);
                break;
            case AutopilotState.Avoiding:
                this.TickAvoiding(deltaTime);
                break;
            case AutopilotState.Paused:
                this.TickPaused(deltaTime);
                break;
            default:
                break;
        }
    }

    // ── Private tick implementations ──────────────────────────────────────────

    private func TickEngaging(dt: Float) -> Void {
        // Allow one frame for steering smoothing to initialise, then cruise.
        this.TransitionTo(AutopilotState.Cruising);
    }

    private func TickCruising(dt: Float) -> Void {
        let distToWaypoint: Float = m_navigator.DistanceToNextWaypoint();

        // Detected an obstacle – switch to avoidance state.
        if m_trafficOpt.IsObstacleAhead() {
            this.TransitionTo(AutopilotState.Avoiding);
            return;
        }

        // Close enough to waypoint – start decelerating.
        if distToWaypoint < AutopilotConfig.BrakingDistanceM() {
            this.TransitionTo(AutopilotState.Approaching);
            return;
        }

        // Normal cruise: apply navigator steering + traffic-aware speed.
        let targetSpeed: Float = m_trafficOpt.GetRecommendedSpeed(
            AutopilotConfig.MaxCruiseSpeedKph());
        m_navigator.ApplySteeringToWaypoint();
        this.ApplyThrottleForSpeed(targetSpeed, dt);

        if AutopilotConfig.VerboseLogging() {
            LogChannel(AutopilotConfig.LogChannel(),
                s"Cruising | dist=\(distToWaypoint) | speed=\(targetSpeed) km/h");
        }
    }

    private func TickApproaching(dt: Float) -> Void {
        let distToWaypoint: Float = m_navigator.DistanceToNextWaypoint();

        // Arrived within arrival radius.
        if distToWaypoint < m_arrivalRadius {
            if m_navigator.AdvanceToNextWaypoint() {
                // There are more waypoints – resume cruising.
                this.TransitionTo(AutopilotState.Cruising);
            } else {
                // No more waypoints – destination reached.
                this.TransitionTo(AutopilotState.Arrived);
                LogChannel(AutopilotConfig.LogChannel(), "Autopilot: DESTINATION REACHED");
            }
            return;
        }

        m_navigator.ApplySteeringToWaypoint();
        this.ApplyThrottleForSpeed(AutopilotConfig.ApproachSpeedKph(), dt);
    }

    private func TickAvoiding(dt: Float) -> Void {
        m_trafficOpt.ApplyAvoidanceManoeuvre(dt);

        // Return to cruising once the path is clear.
        if !m_trafficOpt.IsObstacleAhead() {
            this.TransitionTo(AutopilotState.Cruising);
        }
    }

    private func TickPaused(dt: Float) -> Void {
        if !AutopilotConfig.AutoResumeEnabled() { return; }

        m_pauseTimer -= dt;
        if m_pauseTimer <= 0.0 {
            LogChannel(AutopilotConfig.LogChannel(), "Autopilot RESUMING after override");
            this.TransitionTo(AutopilotState.Cruising);
        }
    }

    // ── Helper utilities ──────────────────────────────────────────────────────

    private func TransitionTo(newState: AutopilotState) -> Void {
        m_state = newState;
    }

    /// Convert km/h to a normalised throttle value and apply it to the vehicle.
    private func ApplyThrottleForSpeed(targetKph: Float, dt: Float) -> Void {
        if !IsDefined(m_vehicle) { return; }

        let currentSpeedMs: Float  = m_vehicle.GetCurrentSpeed();
        let currentKph: Float      = currentSpeedMs * 3.6;
        let delta: Float           = targetKph - currentKph;

        // Positive delta → accelerate; negative → brake.
        if delta > AutopilotConfig.SpeedControlDeadbandKph() {
            m_vehicle.SetThrottle(MinF(delta / AutopilotConfig.ThrottleAccelDivisor(), 1.0));
            m_vehicle.SetBraking(0.0);
        } else if delta < -AutopilotConfig.SpeedControlDeadbandKph() {
            m_vehicle.SetThrottle(0.0);
            m_vehicle.SetBraking(MinF(AbsF(delta) / AutopilotConfig.ThrottleBrakeDivisor(), 1.0));
        } else {
            // Within dead-band – coast with a small throttle to offset rolling resistance.
            m_vehicle.SetThrottle(AutopilotConfig.CoastingThrottleFactor());
            m_vehicle.SetBraking(0.0);
        }
    }
}
