// AutopilotConfig.reds
// 自动驾驶优化 Mod – 配置常量与用户设置
// Autopilot Optimization Mod – Configuration constants and user-tunable settings

module AutopilotOptimization

// ─────────────────────────────────────────────────────────────────────────────
// AutopilotConfig – static configuration class
// All tunable values live here as static methods so the rest of the mod
// references them uniformly as AutopilotConfig.MethodName().
// ─────────────────────────────────────────────────────────────────────────────

public class AutopilotConfig {

    // ── Speed thresholds ─────────────────────────────────────────────────────

    /// Maximum cruise speed on open road (km/h)
    public static func MaxCruiseSpeedKph() -> Float { return 120.0 }

    /// Speed cap when navigating tight urban streets (km/h)
    public static func UrbanSpeedCapKph() -> Float { return 60.0 }

    /// Speed when approaching a waypoint within BrakingDistanceM() metres (km/h)
    public static func ApproachSpeedKph() -> Float { return 30.0 }

    /// Distance from the active waypoint at which braking begins (metres)
    public static func BrakingDistanceM() -> Float { return 40.0 }

    /// Minimum safe gap to the vehicle ahead before the autopilot brakes (metres)
    public static func MinFollowDistanceM() -> Float { return 15.0 }

    // ── Steering & smoothing ─────────────────────────────────────────────────

    /// Steering interpolation factor per tick (0 = no change, 1 = instant snap)
    public static func SteeringSmoothFactor() -> Float { return 0.18 }

    /// Maximum steering angle the autopilot may apply per physics tick (degrees)
    public static func MaxSteerDeltaDeg() -> Float { return 4.0 }

    // ── Obstacle avoidance ───────────────────────────────────────────────────

    /// Lookahead distance for the obstacle-detection ray cast (metres)
    public static func ObstacleLookaheadM() -> Float { return 25.0 }

    /// Radius of the sphere-trace used for obstacle ray-casting (metres).
    /// Roughly half the average vehicle width; increase for extra safety margin.
    public static func ObstacleDetectionRadiusM() -> Float { return 1.2 }

    /// Lateral offset applied when steering around a detected obstacle (metres)
    public static func ObstacleAvoidanceOffsetM() -> Float { return 3.0 }

    /// Interpolation alpha for blending toward the target avoidance offset per
    /// tick (0 = no change, 1 = instant snap).
    public static func AvoidanceOffsetSmoothFactor() -> Float { return 0.1 }

    /// Divisor that converts the lateral avoidance offset (metres) into a
    /// normalised steering bias in [-1, 1].  A value of 5.0 means a 5 m full
    /// offset maps to a ±1 steering command.
    public static func AvoidanceSteeringDivisor() -> Float { return 5.0 }

    /// Normalised throttle applied while executing an avoidance manoeuvre (0–1).
    /// Lower values keep the vehicle cautious around obstacles.
    public static func AvoidanceThrottleFactor() -> Float { return 0.3 }

    /// Per-tick decay rate applied to the avoidance offset once the obstacle
    /// is no longer detected (fraction of current offset retained each tick).
    public static func AvoidanceOffsetDecayRate() -> Float { return 0.85 }

    /// Avoidance offset (metres) below which it is snapped to zero to avoid
    /// a long tail of sub-millimetre corrections.
    public static func AvoidanceOffsetDeadbandM() -> Float { return 0.05 }

    // ── Traffic-light awareness ──────────────────────────────────────────────

    /// Distance at which the autopilot starts to honour traffic lights (metres)
    public static func TrafficLightDetectionRangeM() -> Float { return 35.0 }

    /// Extra hold time after a green signal is detected before accelerating (seconds)
    public static func GreenLightHoldS() -> Float { return 0.5 }

    // ── Speed control dead-band & throttle tuning ────────────────────────────

    /// Speed dead-band (km/h): no throttle or brake change is applied when the
    /// speed error is smaller than this value (prevents oscillation).
    public static func SpeedControlDeadbandKph() -> Float { return 0.5 }

    /// Divisor used to scale the positive speed error into a [0, 1] throttle
    /// value.  A value of 20 means a 20 km/h deficit commands full throttle.
    public static func ThrottleAccelDivisor() -> Float { return 20.0 }

    /// Divisor used to scale the negative speed error into a [0, 1] braking
    /// value.  A value of 30 means a 30 km/h excess commands full braking.
    public static func ThrottleBrakeDivisor() -> Float { return 30.0 }

    /// Tiny coasting throttle applied inside the speed dead-band to compensate
    /// for rolling resistance and maintain momentum on flat roads (0–1).
    public static func CoastingThrottleFactor() -> Float { return 0.05 }

    /// Seconds of driver inactivity before autopilot automatically re-engages
    public static func AutoResumeDelayS() -> Float { return 3.0 }

    /// Whether the mod should automatically re-engage autopilot after a manual
    /// steering/throttle override has been released.
    public static func AutoResumeEnabled() -> Bool { return true }

    // ── Debug / logging ──────────────────────────────────────────────────────

    /// Log channel used by this mod (visible in Cyber Engine Tweaks console)
    public static func LogChannel() -> CName { return n"AutopilotOptimization" }

    /// Set to true to enable verbose tick-level logging (may impact performance)
    public static func VerboseLogging() -> Bool { return false }
}
