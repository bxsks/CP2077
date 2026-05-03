// AutopilotHooks.reds
// 自动驾驶优化 Mod
// Autopilot Optimization Mod – Game method hooks and event integration

module AutopilotOptimization
import AutopilotOptimization.*

// ─────────────────────────────────────────────────────────────────────────────
// Registry – maps a VehicleObject entity ID to its AutopilotController so that
// the same controller is reused each tick rather than re-created.
// ─────────────────────────────────────────────────────────────────────────────

public class AutopilotRegistry {

    private static let s_controllers: array<AutopilotController>;
    private static let s_vehicleIds: array<EntityID>;

    public static func GetOrCreate(vehicle: ref<VehicleObject>) -> ref<AutopilotController> {
        let id: EntityID = vehicle.GetEntityID();
        let i: Int32 = 0;
        while i < ArraySize(AutopilotRegistry.s_vehicleIds) {
            if AutopilotRegistry.s_vehicleIds[i] == id {
                return AutopilotRegistry.s_controllers[i];
            }
            i += 1;
        }
        // Not found – create and register.
        let ctrl: ref<AutopilotController> = AutopilotController.Create(vehicle);
        ArrayPush(AutopilotRegistry.s_vehicleIds,   id);
        ArrayPush(AutopilotRegistry.s_controllers, ctrl);
        return ctrl;
    }

    public static func Remove(vehicle: ref<VehicleObject>) -> Void {
        let id: EntityID = vehicle.GetEntityID();
        let i: Int32 = 0;
        while i < ArraySize(AutopilotRegistry.s_vehicleIds) {
            if AutopilotRegistry.s_vehicleIds[i] == id {
                ArrayErase(AutopilotRegistry.s_vehicleIds,   i);
                ArrayErase(AutopilotRegistry.s_controllers, i);
                return;
            }
            i += 1;
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// VehicleObject – tick hook
// Every physics tick while a vehicle is alive we update its autopilot
// controller if one is active.
// ─────────────────────────────────────────────────────────────────────────────

@wrapMethod(VehicleObject)
protected cb func OnTick(dt: Float) -> Void {
    wrappedMethod(dt);

    let ctrl: ref<AutopilotController> =
        AutopilotRegistry.GetOrCreate(this);
    if ctrl.IsActive() {
        ctrl.OnTick(dt);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// VehicleObject – detect when the vehicle is destroyed / unregistered
// ─────────────────────────────────────────────────────────────────────────────

@wrapMethod(VehicleObject)
protected cb func OnGameDetach() -> Void {
    AutopilotRegistry.Remove(this);
    wrappedMethod();
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerPuppet – detect manual steering/throttle input so autopilot can pause
// ─────────────────────────────────────────────────────────────────────────────

@wrapMethod(PlayerPuppet)
protected cb func OnDriveInputAction(action: ref<DrivingInputAction>) -> Void {
    wrappedMethod(action);

    let vehicle: ref<VehicleObject> = this.GetMountedVehicle();
    if !IsDefined(vehicle) { return; }

    let ctrl: ref<AutopilotController> = AutopilotRegistry.GetOrCreate(vehicle);
    if !ctrl.IsActive() { return; }

    // If the player moves the steering wheel or presses throttle/brake,
    // pause the autopilot.
    if action.IsSteeringInput() || action.IsThrottleInput() || action.IsBrakeInput() {
        ctrl.NotifyManualOverride();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerPuppet – public helpers added to PlayerPuppet for CET / other mods
// ─────────────────────────────────────────────────────────────────────────────

/// Engage the autopilot for the currently-driven vehicle and set `destination`
/// as the target world position.  Returns false if no vehicle is mounted.
@addMethod(PlayerPuppet)
public func EngageVehicleAutopilot(destination: Vector4) -> Bool {
    let vehicle: ref<VehicleObject> = this.GetMountedVehicle();
    if !IsDefined(vehicle) {
        LogChannel(AutopilotConfig.LogChannel(),
                   "EngageVehicleAutopilot: player is not in a vehicle");
        return false;
    }
    let ctrl: ref<AutopilotController> = AutopilotRegistry.GetOrCreate(vehicle);
    ctrl.Engage(destination);
    return true;
}

/// Disengage the autopilot for the currently-driven vehicle.
@addMethod(PlayerPuppet)
public func DisengageVehicleAutopilot() -> Bool {
    let vehicle: ref<VehicleObject> = this.GetMountedVehicle();
    if !IsDefined(vehicle) { return false; }
    let ctrl: ref<AutopilotController> = AutopilotRegistry.GetOrCreate(vehicle);
    ctrl.Disengage();
    return true;
}

/// Returns the current AutopilotState for the driven vehicle, or Inactive when
/// not in a vehicle.
@addMethod(PlayerPuppet)
public func GetVehicleAutopilotState() -> AutopilotState {
    let vehicle: ref<VehicleObject> = this.GetMountedVehicle();
    if !IsDefined(vehicle) { return AutopilotState.Inactive; }
    return AutopilotRegistry.GetOrCreate(vehicle).GetState();
}
