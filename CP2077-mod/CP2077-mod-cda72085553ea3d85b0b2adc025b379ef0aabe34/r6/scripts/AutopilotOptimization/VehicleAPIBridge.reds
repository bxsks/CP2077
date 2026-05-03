// VehicleAPIBridge.reds
// 自动驾驶优化 Mod
// Autopilot Optimization Mod – Game API bridge layer
//
// Defines the TrafficLightQueryResult struct and adds @addMethod extensions to
// VehicleObject and DrivingInputAction that wrap real game APIs where available,
// or provide safe stub implementations where the game does not expose a direct
// native method.  All other mod files depend on the types and methods declared
// here.

module AutopilotOptimization

// ─────────────────────────────────────────────────────────────────────────────
// TrafficLightQueryResult – result of a traffic-light proximity query
// ─────────────────────────────────────────────────────────────────────────────

public struct TrafficLightQueryResult {
    /// Straight-line distance to the nearest traffic light (metres).
    /// Set to 9999 when no light is found within detection range.
    public let distance: Float;
    /// Current colour phase of the nearest light.
    public let state: ETrafficLightColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// VehicleObject – missing-API additions
// ─────────────────────────────────────────────────────────────────────────────

/// Return the vehicle's current speed in metres per second.
/// Wraps VehicleComponent.GetCurrentSpeed() which is available in CP2077 ≥ 2.0.
@addMethod(VehicleObject)
public func GetCurrentSpeed() -> Float {
    let comp: ref<VehicleComponent> = this.GetVehicleComponent();
    if !IsDefined(comp) { return 0.0; }
    return comp.GetCurrentSpeed();
}

/// Apply a normalised steering input in [-1, 1] to the vehicle.
/// Positive = turn right, negative = turn left.
@addMethod(VehicleObject)
public func SetSteering(value: Float) -> Void {
    let comp: ref<VehicleComponent> = this.GetVehicleComponent();
    if !IsDefined(comp) { return; }
    comp.SetDesiredSteeringAngleNorm(ClampF(value, -1.0, 1.0));
}

/// Apply a normalised throttle input in [0, 1] to the vehicle.
@addMethod(VehicleObject)
public func SetThrottle(value: Float) -> Void {
    let comp: ref<VehicleComponent> = this.GetVehicleComponent();
    if !IsDefined(comp) { return; }
    comp.SetThrottleInput(ClampF(value, 0.0, 1.0));
}

/// Apply a normalised braking input in [0, 1] to the vehicle.
@addMethod(VehicleObject)
public func SetBraking(value: Float) -> Void {
    let comp: ref<VehicleComponent> = this.GetVehicleComponent();
    if !IsDefined(comp) { return; }
    comp.SetBrakeInput(ClampF(value, 0.0, 1.0));
}

/// Perform a forward ray cast and return the distance to the nearest
/// dynamic obstacle within `range` metres.  Returns 0 if nothing is hit.
@addMethod(VehicleObject)
public func RayCastForwardDistance(range: Float) -> Float {
    let origin: Vector4  = this.GetWorldPosition();
    let forward: Vector4 = this.GetWorldForward();
    let target: Vector4;
    target.X = origin.X + forward.X * range;
    target.Y = origin.Y + forward.Y * range;
    target.Z = origin.Z + forward.Z * range;
    target.W = 1.0;

    // Use the game's physics trace system.
    let traceResult: TraceResult;
    let traceSucceeded: Bool =
        GameInstance.GetPhysicsSystem(this.GetGame())
            .SphereTraceSingleByChannel(
                origin, target,
                AutopilotConfig.ObstacleDetectionRadiusM(),
                gameTraceChannel.Dynamic,
                traceResult,
                this);                  // ignore self

    if traceSucceeded && traceResult.IsValid() {
        return traceResult.GetHitDistance();
    }
    return 0.0;
}

/// Query the nearest traffic light within `range` metres in front of the
/// vehicle.  Returns a TrafficLightQueryResult with distance=9999 and
/// state=ETrafficLightColor.Green when no light is found.
@addMethod(VehicleObject)
public func QueryNearestTrafficLight(range: Float) -> TrafficLightQueryResult {
    let result: TrafficLightQueryResult;
    result.distance = 9999.0;
    result.state    = ETrafficLightColor.Green;

    let vPos: Vector4    = this.GetWorldPosition();
    let forward: Vector4 = this.GetWorldForward();

    // Gather all traffic lights within 'range' via the game's entity finder.
    let trafficSystem: ref<TrafficSystem> =
        GameInstance.GetTrafficSystem(this.GetGame());
    if !IsDefined(trafficSystem) { return result; }

    let lights: array<ref<TrafficLight>> =
        trafficSystem.GetNearbyTrafficLights(vPos, range);

    let bestDist: Float = 9999.0;
    let i: Int32 = 0;
    while i < ArraySize(lights) {
        let light: ref<TrafficLight> = lights[i];
        if IsDefined(light) {
            let lPos: Vector4  = light.GetWorldPosition();
            let toLight: Vector4;
            toLight.X = lPos.X - vPos.X;
            toLight.Y = lPos.Y - vPos.Y;
            toLight.Z = 0.0;
            toLight.W = 0.0;

            // Only consider lights in the forward hemisphere.
            let dot: Float = toLight.X * forward.X + toLight.Y * forward.Y;
            if dot > 0.0 {
                let dist: Float = SqrtF(
                    toLight.X * toLight.X + toLight.Y * toLight.Y);
                if dist < bestDist {
                    bestDist        = dist;
                    result.distance = dist;
                    result.state    = light.GetCurrentColor();
                }
            }
        }
        i += 1;
    }
    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// DrivingInputAction – helper predicates
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true when this action represents lateral steering input.
@addMethod(DrivingInputAction)
public func IsSteeringInput() -> Bool {
    let name: CName = this.GetName();
    return Equals(name, n"SteeringWheel")
        || Equals(name, n"SteerLeft")
        || Equals(name, n"SteerRight");
}

/// Returns true when this action represents forward throttle input.
@addMethod(DrivingInputAction)
public func IsThrottleInput() -> Bool {
    let name: CName = this.GetName();
    return Equals(name, n"Accelerate")
        || Equals(name, n"Throttle");
}

/// Returns true when this action represents braking input.
@addMethod(DrivingInputAction)
public func IsBrakeInput() -> Bool {
    let name: CName = this.GetName();
    return Equals(name, n"Brake")
        || Equals(name, n"HandBrake");
}
