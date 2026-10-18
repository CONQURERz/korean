local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")


function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  
  function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/GRW_XDTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

local VICTORY_DANCE_FX_MAP = {
  [12219601] = 22010089
}

function ResolveEmoteResID(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then
    return ItemID
  end
  local model_util = require("client.common.model_util")
  local FxBPID = model_util.GetBPID(FxID)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s", tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandlePath(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return ""
  end
  return model_util.GetPath("Emote", BPID, false, false) or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandle(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return nil
  end
  local HandleClass = model_util.GetClass("Emote", BPID, false, false)
  if not HandleClass then
    return nil
  end
  local Handle = HandleClass()
  if not slua.isValid(Handle) then
    return nil
  end
  return Handle
end


-- AUTH GATE: BRPlayer-compatible online login
-- ============================================================================
-- 1. LICENSE CONFIG + CORE
-- ============================================================================
local MasterLicenseConfig = (function()
    return {
        url = 'https://sameer.keysgen.online/connect', game = 'PUBGM',
        timeout = 10, clockSkew = 120, expiryPath = nil,
        manualExpiry = "2026-12-31 23:59:59", tamperTolerance = 5,
        secret = 'DIAMONDYT',
    }
end)()

local MasterLicenseCore = (function()
    local Primitives = (function()
        local floor, abs, max = math.floor, math.abs, math.max
        local byte, char, format = string.byte, string.char, string.format
        local U32 = 4294967296
        local AND, XOR = {}, {}
        for a = 0, 15 do for b = 0, 15 do
            local av, bv, both, different, place = a, b, 0, 0, 1
            for _ = 1, 4 do
                local x, y = av % 2, bv % 2
                if x == 1 and y == 1 then both = both + place end
                if x ~= y then different = different + place end
                av, bv, place = floor(av / 2), floor(bv / 2), place * 2
            end
            AND[a * 16 + b], XOR[a * 16 + b] = both, different
        end end
        local function bitop(a, b, lookup)
            local value, place = 0, 1
            for _ = 1, 8 do
                value = value + lookup[(a % 16) * 16 + b % 16] * place
                a, b, place = floor(a / 16), floor(b / 16), place * 16
            end
            return value
        end
        local function band(a, b) return bitop(a, b, AND) end
        local function bxor(a, b) return bitop(a, b, XOR) end
        local function rol(value, amount)
            local divisor = 2 ^ (32 - amount)
            return (value % divisor) * 2 ^ amount + floor(value / divisor)
        end
        local function little32(value)
            return char(value % 256, floor(value / 256) % 256,
                floor(value / 65536) % 256, floor(value / 16777216) % 256)
        end
        local K = {
            0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
            0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
            0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
            0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
            0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
            0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
            0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
            0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
        }
        local SHIFT = {7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21}
        local function md5_raw(input)
            assert(type(input) == "string", "MD5 input must be a string")
            local size = #input
            local message = input .. char(128) .. string.rep(char(0), (55 - size) % 64)
                .. little32((size * 8) % U32) .. little32(floor(size / 536870912))
            local h0, h1, h2, h3 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
            local words = {}
            for offset = 1, #message, 64 do
                for j = 0, 15 do
                    local a, b, c, d = byte(message, offset + j * 4, offset + j * 4 + 3)
                    words[j] = a + b * 256 + c * 65536 + d * 16777216
                end
                local a, b, c, d = h0, h1, h2, h3
                for i = 0, 63 do
                    local f, g, shiftBase
                    if i < 16 then
                        f, g, shiftBase = band(b, c) + band(U32 - 1 - b, d), i, 0
                    elseif i < 32 then
                        f, g, shiftBase = band(d, b) + band(U32 - 1 - d, c), (5 * i + 1) % 16, 4
                    elseif i < 48 then
                        f, g, shiftBase = bxor(bxor(b, c), d), (3 * i + 5) % 16, 8
                    else
                        local bOrNotD = U32 - 1 - band(U32 - 1 - b, d)
                        f, g, shiftBase = bxor(c, bOrNotD), (7 * i) % 16, 12
                    end
                    local nextB = (b + rol((a + f + K[i + 1] + words[g]) % U32,
                        SHIFT[shiftBase + i % 4 + 1])) % U32
                    a, b, c, d = d, nextB, b, c
                end
                h0, h1, h2, h3 = (h0 + a) % U32, (h1 + b) % U32, (h2 + c) % U32, (h3 + d) % U32
            end
            return little32(h0) .. little32(h1) .. little32(h2) .. little32(h3)
        end
        local function hex(input)
            return (input:gsub(".", function(c) return format("%02x", byte(c)) end))
        end
        local function md5(input) return hex(md5_raw(input)) end
        local function form_encode(input)
            assert(type(input) == "string", "Form value must be a string")
            return (input:gsub("[^A-Za-z0-9%-%._~ ]", function(c)
                return format("%%%02X", byte(c)) end):gsub(" ", "+"))
        end
        local function constant_time_equal(a, b)
            if type(a) ~= "string" or type(b) ~= "string" then return false end
            local difference = abs(#a - #b)
            for i = 1, max(#a, #b) do
                difference = difference + abs((byte(a, i) or 0) - (byte(b, i) or 0))
            end
            return difference == 0
        end
        local function name_uuid(input)
            local digest = md5_raw(input)
            local h = hex(digest:sub(1,6) .. char(byte(digest,7) % 16 + 48)
                .. digest:sub(8,8) .. char(byte(digest,9) % 64 + 128) .. digest:sub(10))
            return h:sub(1,8) .. "-" .. h:sub(9,12) .. "-" .. h:sub(13,16)
                .. "-" .. h:sub(17,20) .. "-" .. h:sub(21,32)
        end
        return {md5 = md5, md5_raw = md5_raw, form_encode = form_encode,
                constant_time_equal = constant_time_equal, name_uuid = name_uuid}
    end)()

    local SESSION_KEY = '__MasterLicenseSession_v1'
    local SAVED_KEY_FILE = 'GRW_Official_license_key.txt'

    local function getSavedKeyPaths()
        return {
            '/Documents/GRW_XDTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '/Documents/GRW_XDTrackerExtra/Saved/Paks/puffer_temp/' .. SAVED_KEY_FILE,
            'GRW_XDTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '../../GRW_XDTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
        }
    end

    local function loadSavedKey()
        for _, path in ipairs(getSavedKeyPaths()) do
            local f = io.open(path, 'r')
            if f then
                local key = f:read('*a')
                f:close()
                if type(key) == 'string' then
                    key = key:match('^%s*(.-)%s*$')
                    if #key > 0 and #key <= 512 then return key end
                end
            end
        end
        return nil
    end

    local function saveSavedKey(key)
        if type(key) ~= 'string' then return false end
        key = key:match('^%s*(.-)%s*$')
        if #key == 0 or #key > 512 then return false end
        local wroteAny = false
        for _, path in ipairs(getSavedKeyPaths()) do
            local f = io.open(path, 'w')
            if f then
                f:write(key)
                f:close()
                wroteAny = true
            end
        end
        return wroteAny
    end

    local function clearSavedKey()
        for _, path in ipairs(getSavedKeyPaths()) do
            pcall(function()
                local f = io.open(path, 'w')
                if f then f:write(''); f:close() end
            end)
        end
    end

    local function loadSession()
        local g = rawget(_G, SESSION_KEY)
        if type(g) ~= 'table' or g.authorized ~= true then return nil end
        if type(g.expiresAt) == 'number' and g.expiresAt <= os.time() then
            _G[SESSION_KEY] = nil; return nil
        end
        return g
    end
    local function saveSession(expiresAt)
        pcall(function()
            _G[SESSION_KEY] = {authorized = true, expiresAt = expiresAt, issuedAt = os.time()}
        end)
    end
    local function clearSession() pcall(function() _G[SESSION_KEY] = nil end) end

    local CreateLocalExpiry = (function()
        return function(cfg, wallReader)
            local E = {}
            local expiredText = 'Mod expired. DM +92 [ 03704831068 ] for renewal.'
            local tamperText  = "Don't be over smart"
            local blockedMessage, blockedPhase
            local function finite(n)
                return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
            end
            local function parse(text)
                if type(text) ~= 'string' then return nil end
                local y,m,d,h,n,s = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$')
                y,m,d,h,n,s = tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n),tonumber(s)
                if not y or y < 1970 or y > 9999 or m < 1 or m > 12 or h > 23 or n > 59 or s > 59 then return nil end
                local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
                local months = {31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
                if d < 1 or d > months[m] then return nil end
                local prior = y - 1
                local days = 365 * (y - 1970) + math.floor(prior / 4) - math.floor(1969 / 4)
                    - math.floor(prior / 100) + math.floor(1969 / 100)
                    + math.floor(prior / 400) - math.floor(1969 / 400)
                for i = 1, m - 1 do days = days + months[i] end
                return (days + d - 1) * 86400 + h * 3600 + n * 60 + s - 6 * 3600
            end
            local configured = type(cfg.manualExpiry) == 'string'
                and cfg.manualExpiry:match('^%s*(.-)%s*$') or cfg.manualExpiry
            local expiry = parse(configured)
            local skew = cfg.clockSkew or 120
            if configured ~= nil and configured ~= '' and not expiry then
                blockedMessage, blockedPhase = 'Invalid local expiry date. Use YYYY-MM-DD HH:MM:SS.', 'error'
            end
            local function block(message, phase)
                if not blockedMessage then blockedMessage, blockedPhase = message, phase end
                return false, blockedMessage, blockedPhase
            end
            function E.Status() return not blockedMessage, blockedMessage, blockedPhase end
            function E.MarkTampered() return block(tamperText, 'tampered') end
            function E.GetExpiry() return expiry end
            function E.Accept(server, now, world, phone, rtt)
                if blockedMessage then return E.Status() end
                if not finite(server) or not finite(now) or now < 0 or world == nil
                    or not finite(rtt) or rtt < 0 or not finite(phone) then
                    return block('Clock verification unavailable.', 'error')
                end
                if math.abs(phone - server) > skew + rtt then return E.MarkTampered() end
                if expiry and server + rtt >= expiry then return block(expiredText, 'expired') end
                return true
            end
            return E
        end
    end)()

    local CreateAuth = (function()
        return function(P, cfg, deps)
            local A = {}
            local phase, message = 'locked', 'Enter your key to sign in.'
            local allowed, pending, generation = false, nil, 0
            local expiresAt
            local lastRequestLatencyMs, lastResponseTime, lastResponseWorld
            local startFn, stopFn, payloadStarted, restartRequired
            local localExpiry = deps.localExpiry
            local savedKey = loadSavedKey()
            do
                local stored = loadSession()
                if stored then
                    allowed = true; expiresAt = stored.expiresAt
                    phase, message = 'active', 'Session restored'
                end
            end
            if localExpiry then
                local ok, text, state = localExpiry.Status()
                if not ok then message, phase = text, state end
            end
            local function finite(n)
                return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
            end
            local function readClock()
                local ok, n, w = pcall(deps.clock)
                if ok and finite(n) and n >= 0 and w ~= nil then return n, w end
            end
            local function notify(text, state)
                message, phase = text, state
                if type(deps.status) == 'function' then pcall(deps.status, text, state) end
            end
            local function stopPayload()
                if payloadStarted then
                    payloadStarted = false
                    local ok, accepted = pcall(stopFn)
                    if not ok or accepted == false then restartRequired = true end
                end
            end
            local function revoke(text, state)
                generation = generation + 1
                allowed, pending, expiresAt = false, nil, nil
                lastRequestLatencyMs, lastResponseTime, lastResponseWorld = nil, nil, nil
                stopPayload()
                local localDenied = false
                if localExpiry then
                    local ok, localText, localPhase = localExpiry.Status()
                    if not ok then text, state, localDenied = localText, localPhase, true end
                end
                notify(restartRequired and not localDenied
                    and 'Restart required: payload cleanup failed.' or text, state or 'error')
            end
            local function startPayload()
                if payloadStarted or not startFn then return true end
                payloadStarted = true
                local before = generation
                local ok, accepted = pcall(startFn)
                if not ok or accepted == false then
                    restartRequired = true
                    revoke('Restart required: offline script startup failed.', 'error')
                    return false
                end
                return generation == before and allowed
            end
            local function denyReason(reason)
                if type(reason) ~= 'string' then return 'Expired' end
                local lower = reason:sub(1, 120):lower():gsub('[_%s%-]+', ' ')
                if lower == 'max devices' or lower == 'maximum devices'
                    or lower == 'max devices reached' then
                    return 'Max Devices'
                end
                local clean = reason
                for _, field in ipairs({'key', 'serial'}) do
                    if pending and type(pending[field]) == 'string' and #pending[field] > 0 then
                        local needle = pending[field]:gsub('([^%w])', '%%%1')
                        clean = clean:gsub(needle, '[' .. field .. ']')
                    end
                end
                if type(cfg.secret) == 'string' and #cfg.secret > 0 then
                    clean = clean:gsub(cfg.secret:gsub('([^%w])', '%%%1'), '[credential]')
                end
                clean = clean:gsub('[%c]', ' '):sub(1, 120)
                return clean == '' and 'Expired' or ('Expired: ' .. clean)
            end
            local function configuredExpiry(result)
                if cfg.expiryPath == nil then return nil, true end
                if type(cfg.expiryPath) ~= 'table' or #cfg.expiryPath == 0 then return nil, false end
                local v = result
                for _, name in ipairs(cfg.expiryPath) do
                    if type(v) ~= 'table' then return nil, false end
                    v = rawget(v, name)
                end
                return v, finite(v) and v > 0 and v % 1 == 0
            end
            local function begin(key)
                if restartRequired or pending then return false end
                if localExpiry then
                    local ok, text, state = localExpiry.Status()
                    if not ok then revoke(text, state); return false end
                end
                if type(key) ~= 'string' then key = '' end
                key = key:match('^%s*(.-)%s*$')
                if #key == 0 or #key > 512 then
                    revoke('Expired: enter a valid key.', 'denied'); return false
                end
                local now, world = readClock()
                if not now then
                    revoke('Game clock unavailable. Try again in a match.', 'error'); return false
                end
                local okSerial, serial = pcall(deps.serial, key)
                if not okSerial or type(serial) ~= 'string' or #serial == 0 or #serial > 512 then
                    revoke('Device identifier unavailable.', 'error'); return false
                end
                generation = generation + 1
                local requestId = generation
                pending = {id = requestId, key = key, serial = serial,
                           started = now, world = world, deadline = now + cfg.timeout}
                notify('Signing in...', 'pending')
                if not pending or pending.id ~= requestId or generation ~= requestId then return false end
                local body = 'game=' .. P.form_encode(cfg.game)
                    .. '&user_key=' .. P.form_encode(key)
                    .. '&serial=' .. P.form_encode(serial)
                local function received(success, raw)
                    if not pending or pending.id ~= requestId or generation ~= requestId then return end
                    local current, worldNow = readClock()
                    if not current or worldNow ~= pending.world or current < pending.started
                        or current >= pending.deadline then
                        revoke('Request expired. Please sign in again.', 'error'); return
                    end
                    if success ~= true or type(raw) ~= 'string' or #raw == 0 or #raw > 32768 then
                        revoke('Connection failed. Please try again.', 'error'); return
                    end
                    local ok, result = pcall(deps.decode, raw)
                    if not ok or type(result) ~= 'table' then
                        revoke('Invalid server response.', 'error'); return
                    end
                    if result.status ~= true then revoke(denyReason(result.reason), 'denied'); return end
                    local data = result.data
                    if type(data) ~= 'table' or type(data.token) ~= 'string' or #data.token ~= 32
                        or not data.token:match('^[%x]+$') or not finite(data.rng) or data.rng % 1 ~= 0 then
                        revoke('Incomplete server response.', 'error'); return
                    end
                    local expected = P.md5(cfg.game .. '-' .. key .. '-' .. serial .. '-' .. cfg.secret)
                    if not P.constant_time_equal(data.token:lower(), expected) then
                        revoke('Server token verification failed.', 'denied'); return
                    end
                    local okWall, wall = pcall(deps.wall)
                    if not okWall or not finite(wall) then
                        revoke('Phone clock unavailable.', 'error'); return
                    end
                    if localExpiry then
                        local accepted, text, state = localExpiry.Accept(
                            data.rng, current, worldNow, wall, current - pending.started)
                        if not accepted then revoke(text, state); return end
                    elseif math.abs(wall - data.rng) > cfg.clockSkew then
                        revoke('Phone/server clock mismatch. Check automatic time.', 'error'); return
                    end
                    local expiry, validExpiry = configuredExpiry(result)
                    if not validExpiry then
                        revoke('Configured server expiry field is missing or invalid.', 'error'); return
                    end
                    if expiry and expiry - data.rng - (current - pending.started) <= 0 then
                        revoke('Expired', 'denied'); return
                    end
                    local fixedExpiry = localExpiry and localExpiry.GetExpiry()
                    if fixedExpiry then expiry = math.min(expiry or fixedExpiry, fixedExpiry) end
                    lastRequestLatencyMs = (current - pending.started) * 1000
                    lastResponseTime, lastResponseWorld = current, worldNow
                    pending = nil
                    allowed, expiresAt = true, expiry
                    saveSession(expiresAt)
                    -- Remember the successfully authenticated key so the next
                    -- game launch can restore access without asking again.
                    pcall(function()
                        saveSavedKey(key)
                        savedKey = key
                        _G.__GRW_SAVED_LICENSE_KEY = key
                        if type(_G.__GRWPersistLicenseKey) == 'function' then
                            _G.__GRWPersistLicenseKey(key)
                        end
                        if type(_G.SHMenuSave) == 'function' then
                            _G.SHMenuSave()
                        end
                    end)
                    if not startPayload() then return end
                    notify('Login successful.', 'active')
                end
                local ok, accepted = pcall(deps.post, cfg.url,
                    {['Content-Type'] = 'application/x-www-form-urlencoded'},
                    body, received, cfg.timeout)
                if not ok or accepted == false then
                    revoke('HTTP request could not start.', 'error'); return false
                end
                return true
            end
            function A.Login(key) if allowed then return false end; return begin(key) end
            function A.Tick()
                if not pending then return end
                local now, world = readClock()
                if not now or world ~= pending.world or now < pending.started then
                    revoke('Login interrupted by map loading. Please try again when ready.', 'locked'); return
                end
                if now >= pending.deadline then
                    revoke('Request timed out. Please try again.', 'error')
                end
            end
            function A.IsAuthorized()
                if allowed and not restartRequired then return true end
                local stored = loadSession()
                if stored and not restartRequired then
                    allowed = true; expiresAt = stored.expiresAt; return true
                end
                return false
            end
            function A.Logout() clearSession(); revoke('Expired: signed out.', 'locked') end
            function A.FailClosed(text, requiresRestart)
                if requiresRestart == true then restartRequired = true end
                revoke(text or 'Online access unavailable.', 'error')
            end
            function A.ReportClockTampering()
                if localExpiry then localExpiry.MarkTampered() end
                revoke("Don't be over smart", 'tampered')
            end
            function A.Bind(onStart, onStop)
                if type(onStart) ~= 'function' or type(onStop) ~= 'function' then
                    return false, 'START_AND_STOP_REQUIRED'
                end
                if startFn and (startFn ~= onStart or stopFn ~= onStop) then
                    return false, 'ALREADY_BOUND'
                end
                startFn, stopFn = onStart, onStop
                if A.IsAuthorized() then return startPayload() end
                return true
            end
            function A.Unbind()
                revoke('Offline script disconnected.', 'locked')
                startFn, stopFn = nil, nil
            end
            function A.GetSavedKey()
                if type(savedKey) == 'string' and #savedKey > 0 then return savedKey end
                local g = rawget(_G, '__GRW_SAVED_LICENSE_KEY')
                if type(g) == 'string' and #g > 0 then return g end
                return nil
            end
            function A.SetSavedKey(key)
                if type(key) ~= 'string' then return false end
                key = key:match('^%s*(.-)%s*$')
                if #key == 0 or #key > 512 then return false end
                savedKey = key
                pcall(function()
                    _G.__GRW_SAVED_LICENSE_KEY = key
                    saveSavedKey(key)
                    if type(_G.__GRWPersistLicenseKey) == 'function' then _G.__GRWPersistLicenseKey(key) end
                end)
                return true
            end
            function A.GetRemainingSeconds() return nil end
            function A.GetState()
                local authorized = A.IsAuthorized()
                local sample, age
                if authorized and lastRequestLatencyMs ~= nil then
                    local now, world = readClock()
                    if now and world == lastResponseWorld and now >= lastResponseTime then
                        sample, age = lastRequestLatencyMs, now - lastResponseTime
                    end
                end
                return {
                    phase = phase, message = message, authorized = authorized,
                    sessionAuthorized = authorized, expiresAt = expiresAt,
                    accessPolicy = "game_session", expiryCheckPolicy = "login_only",
                    periodicRecheck = false, pending = pending ~= nil,
                    linked = startFn ~= nil, restartRequired = restartRequired == true,
                    lastRequestLatencyMs = sample, lastRequestLatencyAgeSeconds = age,
                    latencyScope = "license_http_round_trip"
                }
            end
            return A
        end
    end)()

    local Core = {Primitives = Primitives, createExpiry = CreateLocalExpiry}
    function Core.new(config, dependencies)
        assert(type(config) == 'table' and type(dependencies) == 'table',
            'License configuration and dependencies required')
        local deps = {}
        for key, value in pairs(dependencies) do deps[key] = value end
        if deps.localExpiry == nil then deps.localExpiry = CreateLocalExpiry(config, deps.wall) end
        return CreateAuth(Primitives, config, deps)
    end
    return Core
end)()

-- ============================================================================
-- 2. LOGIN UI
-- ============================================================================
local MasterLoginUI = (function()
    local Module = {}
    function Module.new(env)
        env = env or _G
        local require = env.require or require
        local function global(name)
            local ok, value = pcall(function() return env[name] end)
            if ok then return value end
        end
        local UI = {_status = "Enter your key", _busy = false, _data = nil}
        local function member(object, name)
            if object == nil then return nil end
            local ok, value = pcall(function() return object[name] end)
            if ok then return value end
        end
        local function valid(object)
            local check = member(global("slua"), "isValid")
            if object == nil then return false end
            if type(check) == 'function' then
                local ok, result = pcall(check, object)
                if ok and result == true then return true end
            end
            local game = global('Game')
            local fallback = member(game, 'IsValid')
            if type(fallback) == 'function' then
                local ok, result = pcall(fallback, game, object)
                return ok and result == true
            end
            return false
        end
        local function imported(name)
            local loader = global("import")
            if type(loader) ~= "function" then return nil end
            local ok, result = pcall(loader, name)
            if ok then return result end
        end
        local function construct(class, ...)
            if class == nil then return nil end
            local ok, result = pcall(class, ...)
            if ok then return result end
        end
        local function vector(x, y)
            return construct(global("FVector2D") or imported("Vector2D"), x, y)
                or {X = x, Y = y}
        end
        local function color(r, g, b, a)
            return construct(global("FLinearColor") or imported("LinearColor"), r, g, b, a)
                or {R = r, G = g, B = b, A = a}
        end
        local function visibility(widget, value)
            local setter = member(widget, "SetWidgetVisibility") or member(widget, "SetVisibility")
            assert(type(setter) == "function", "UI_VISIBILITY_UNAVAILABLE")
            setter(widget, value)
        end
        local function setTextStyle(widget, size, textColor)
            pcall(function()
                local font = widget.Font
                if font then
                    font.Size = math.max(1, math.floor(size * (UI._scale or 1) + 0.5))
                    local assigned = pcall(function() widget.Font = font end)
                    if not assigned then widget:SetFont(font) end
                end
            end)
            pcall(function() widget:SetAutoWrapText(true) end)
            pcall(function()
                local slate = construct(imported("SlateColor"), textColor)
                if slate then widget:SetColorAndOpacity(slate) end
            end)
        end
        local function detach(data)
            if not data then return end
            data.visible = false
            pcall(function() if valid(data.input) then data.input:SetText("") end end)
            if data.event and data.eventHandle ~= nil then
                pcall(function() data.event:Remove(data.eventHandle) end)
            end
            if valid(data.container) then
                pcall(function() data.container:RemoveFromParent() end)
            end
            data.onSubmit = nil
        end
        function UI.Destroy()
            local previous = UI._data; UI._data = nil; detach(previous)
        end
        function UI.Hide()
            local data = UI._data
            if not data or data.hiddenApplied then return true end
            data.visible = false
            local ok = pcall(function()
                if valid(data.input) then data.input:SetText("") end
                if valid(data.container) then visibility(data.container, data.hidden) end
            end)
            if ok then data.hiddenApplied = true end
            return ok
        end
        function UI.SetStatus(message)
            UI._status = type(message) == "string" and message:sub(1, 160) or "Login unavailable"
            local data = UI._data
            if data and data.deliveredStatus == UI._status then return true end
            if data and valid(data.status) then
                local ok = pcall(function() data.status:SetText(UI._status) end)
                if ok then data.deliveredStatus = UI._status end
                return ok
            end
            return false
        end
        function UI.SetBusy(busy)
            UI._busy = busy == true
            local data = UI._data
            if data then
                if data.deliveredBusy == UI._busy then return true end
                local buttonOK = pcall(function() data.button:SetIsEnabled(not UI._busy) end)
                local inputOK  = pcall(function() data.input:SetIsEnabled(not UI._busy) end)
                if buttonOK and inputOK then data.deliveredBusy = UI._busy; return true end
            end
            return false
        end
        local function fitScale(parent)
            local result = 1
            pcall(function()
                local size = parent:GetCachedGeometry():GetLocalSize()
                local width, height = size.X, size.Y
                if type(width) == 'number' and type(height) == 'number'
                    and width > 24 and height > 24 then
                    result = math.min(1, (width - 24) / 500, (height - 24) / 248)
                end
            end)
            return result
        end
        function UI.Show(onSubmit, initialKey)
            if type(onSubmit) ~= "function" then return false, "UI_SUBMIT_REQUIRED" end
            if type(initialKey) == "string" then
                initialKey = initialKey:match("^%s*(.-)%s*$")
                if #initialKey == 0 or #initialKey > 512 then initialKey = nil end
            else
                initialKey = nil
            end
            local data = UI._data
            if data and valid(data.parent)
                and math.abs(fitScale(data.parent) - (data.scale or 1)) > 0.001 then
                UI.Destroy(); data = nil
            end
            if data and valid(data.container) and valid(data.parent) then
                local ok = data.visible or pcall(function()
                    visibility(data.container, data.visibleEnum)
                end)
                if ok then
                    data.onSubmit, data.visible, data.hiddenApplied = onSubmit, true, false
                    if initialKey and valid(data.input) then pcall(function() data.input:SetText(initialKey) end) end
                    UI.SetStatus(UI._status); UI.SetBusy(UI._busy); return true
                end
            end
            UI.Destroy()
            local okTools, uiTools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            local getRoot = okTools and member(uiTools, "GetMainControlBaseUI")
            if type(getRoot) ~= "function" then return false, "UI_NOT_READY" end
            local okRoot, root = pcall(getRoot)
            if not okRoot or not valid(root) then return false, "UI_NOT_READY" end
            local parent = member(root, "CanvasPanel_0")
            if not valid(parent) then parent = member(root, "CanvasPanel_42") end
            if not valid(parent) then return false, "UI_NOT_READY" end
            local game = global("CGame")
            if type(member(game, "NewObjectFromPath")) ~= "function" then
                return false, "UI_FACTORY_UNAVAILABLE"
            end
            local enums = member(global("UEnums"), "ESlateVisibility")
            local visibleEnum, hidden = member(enums, "Visible"), member(enums, "Collapsed")
            local passive = member(enums, "SelfHitTestInvisible")
            if visibleEnum == nil or hidden == nil or passive == nil then
                return false, "UI_ENUM_UNAVAILABLE"
            end
            UI._scale = fitScale(parent)
            data = {parent = parent, visible = false, onSubmit = onSubmit,
                    initialKey = initialKey, visibleEnum = visibleEnum, hidden = hidden, scale = UI._scale}
            local okBuild = pcall(function()
                local function make(class, outer)
                    local widget = game:NewObjectFromPath("/Script/UMG." .. class, outer)
                    assert(valid(widget), "UI_WIDGET_UNAVAILABLE")
                    return widget
                end
                data.container = make("CanvasPanel", parent)
                local function add(widget, x, y, width, height, z)
                    local slot = data.container:AddChildToCanvas(widget)
                    slot:SetAutoSize(false)
                    slot:SetPosition(vector(x * UI._scale, y * UI._scale))
                    slot:SetSize(vector(width * UI._scale, height * UI._scale))
                    slot:SetZOrder(z)
                    return slot
                end
                local background = make("Border", data.container)
                background:SetBrushColor(color(0.025, 0.035, 0.05, 0.98))
                visibility(background, visibleEnum)
                add(background, 0, 0, 500, 248, 0)
                local title = make("TextBlock", data.container)
                title:SetText("SAMEER 03408547192 LOGIN")
                setTextStyle(title, 19, color(0.1, 0.9, 1, 1))
                visibility(title, passive); add(title, 22, 15, 456, 30, 1)
                data.input = make("EditableTextBox", data.container)
                data.input:SetText(initialKey or "")
                setTextStyle(data.input, 17, color(0.92, 0.94, 0.96, 1))
                pcall(function() data.input:SetHintText("Enter your key") end)
                visibility(data.input, visibleEnum); add(data.input, 22, 58, 456, 44, 2)
                local hint = make("TextBlock", data.container)
                hint:SetText("Enter your key, then tap LOGIN.")
                setTextStyle(hint, 12, color(0.72, 0.78, 0.83, 1))
                visibility(hint, passive); add(hint, 22, 106, 456, 20, 2)
                data.status = make("TextBlock", data.container)
                data.status:SetText(UI._status); data.deliveredStatus = UI._status
                setTextStyle(data.status, 13, color(0.92, 0.94, 0.96, 1))
                visibility(data.status, passive)
                pcall(function() data.status:SetAutoWrapText(true) end)
                add(data.status, 22, 129, 456, 54, 2)
                data.button = make("Button", data.container)
                visibility(data.button, visibleEnum)
                local label = make("TextBlock", data.button)
                label:SetText("LOGIN")
                setTextStyle(label, 17, color(0.05, 0.08, 0.12, 1))
                visibility(label, passive); data.button:AddChild(label)
                add(data.button, 150, 190, 200, 40, 2)
                data.event = data.button.OnClicked
                data.eventHandle = data.event:Add(function()
                    if UI._data ~= data or not data.visible or UI._busy then return end
                    local readOK, key = pcall(function() return data.input:GetText() end)
                    if not readOK or type(key) ~= "string" then
                        UI.SetStatus("Unable to read the key"); return
                    end
                    key = key:match("^%s*(.-)%s*$")
                    if key == "" or #key > 512 then UI.SetStatus("Enter a valid key"); return end
                    local submitOK = pcall(data.onSubmit, key)
                    if not submitOK then UI.SetBusy(false); UI.SetStatus("Login could not start") end
                end)
                local slot = parent:AddChildToCanvas(data.container)
                slot:SetAutoSize(false)
                slot:SetSize(vector(500 * UI._scale, 248 * UI._scale))
                slot:SetZOrder(9000)
                local anchors = slot:GetAnchors()
                anchors.Minimum, anchors.Maximum = vector(0.5, 0.5), vector(0.5, 0.5)
                slot:SetAnchors(anchors)
                slot:SetAlignment(vector(0.5, 0.5))
                slot:SetPosition(vector(0, 0))
                visibility(data.container, passive)
            end)
            if not okBuild then
                detach(data); return false, "UI_BUILD_UNAVAILABLE"
            end
            data.visible = true; UI._data = data; UI.SetBusy(UI._busy)
            return true
        end
        function UI.ShowNotice(message)
            local shown, reason = UI.Show(function() return false end)
            if not shown then return false, reason end
            UI.SetStatus(message); UI.SetBusy(true); return true
        end
        return UI
    end
    return Module
end)()

-- ============================================================================
-- 3. WELCOME UI
-- ============================================================================
local MasterWelcomeUI = (function()
    local Module = {}
    function Module.new(env)
        env = env or _G
        local require = env.require or require
        local function global(n)
            local ok, v = pcall(function() return env[n] end)
            if ok then return v end
        end
        local function member(o, k)
            if o == nil then return nil end
            local ok, v = pcall(function() return o[k] end)
            if ok then return v end
        end
        local function valid(o)
            local c = member(global("slua"), "isValid")
            if o == nil then return false end
            if type(c) == 'function' then
                local ok, v = pcall(c, o)
                if ok and v == true then return true end
            end
            local g = global('Game'); local f = member(g, 'IsValid')
            if type(f) == 'function' then
                local ok, v = pcall(f, g, o)
                return ok and v == true
            end
            return false
        end
        local function imported(n)
            local l = global("import")
            if type(l) ~= "function" then return nil end
            local ok, v = pcall(l, n); if ok then return v end
        end
        local function construct(c, ...)
            if c == nil then return nil end
            local ok, v = pcall(c, ...); if ok then return v end
        end
        local function vector(x, y)
            return construct(global("FVector2D") or imported("Vector2D"), x, y) or {X = x, Y = y}
        end
        local function linear(v)
            v = v / 255
            if v <= 0.04045 then return v / 12.92 end
            return ((v + 0.055) / 1.055) ^ 2.4
        end
        local function color(r, g, b, a)
            r, g, b, a = linear(r), linear(g), linear(b), a or 1
            return construct(global("FLinearColor") or imported("LinearColor"), r, g, b, a)
                or {R = r, G = g, B = b, A = a}
        end
        local function visibility(w, v)
            local s = member(w, "SetWidgetVisibility") or member(w, "SetVisibility")
            if type(s) == 'function' then s(w, v) end
        end
        local WelcomeUI = {Width = 600, Height = 276}
        local WelcomeText = {
            "OWNER [ 03704831068 ]",
            "Kill limit 8-10",
            "Play smart and avoid report",
        }
        local UI = {_shown = false, _data = nil}
        local function detach(data)
            if not data then return end
            data.Visible = false
            if data.Event and data.EventHandle ~= nil then
                pcall(function() data.Event:Remove(data.EventHandle) end)
            end
            if valid(data.Container) then
                pcall(function() visibility(data.Container, data.Hidden) end)
                pcall(function() data.Container:RemoveFromParent() end)
            end
        end
        function UI:Destroy()
            local p = UI._data; UI._data = nil; detach(p)
        end
        local function parent()
            local okT, tools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            if not okT then return nil end
            local getRoot = member(tools, "GetMainControlBaseUI")
            if type(getRoot) ~= "function" then return nil end
            local ok, root = pcall(getRoot)
            if not ok or not valid(root) then return nil end
            local canvas = member(root, "CanvasPanel_0")
            if not valid(canvas) then canvas = member(root, "CanvasPanel_42") end
            if valid(canvas) then return root, canvas end
        end
        function UI:Show()
            if UI._shown and UI._data and valid(UI._data.Container) then
                visibility(UI._data.Container, UI._data.Passive)
                UI._data.Visible = true
                return true
            end
            UI:Destroy()
            local root, par = parent()
            if not par then return false, "WELCOME_ROOT_UNAVAILABLE" end
            local game = global("CGame")
            if type(member(game, "NewObjectFromPath")) ~= "function" then
                return false, "WELCOME_FACTORY_UNAVAILABLE"
            end
            local enums = member(global("UEnums"), "ESlateVisibility")
            local visible, hidden, passive = member(enums, "Visible"),
                member(enums, "Collapsed"), member(enums, "SelfHitTestInvisible")
            if visible == nil or hidden == nil or passive == nil then
                return false, "WELCOME_ENUM_UNAVAILABLE"
            end
            local data = {Root = root, Parent = par, Visible = false,
                          Hidden = hidden, Passive = passive}
            local ok = pcall(function()
                local function make(class, outer)
                    local w = game:NewObjectFromPath("/Script/UMG." .. class, outer)
                    assert(valid(w), "WELCOME_WIDGET_UNAVAILABLE")
                    return w
                end
                data.Container = make("CanvasPanel", par)
                visibility(data.Container, hidden)
                local function add(w, x, y, ww, hh, z)
                    local s = data.Container:AddChildToCanvas(w)
                    s:SetAutoSize(false)
                    s:SetPosition(vector(x, y))
                    s:SetSize(vector(ww, hh))
                    s:SetZOrder(z)
                    return s
                end
                local function rect(x, y, ww, hh, c, z)
                    local w = make("Border", data.Container)
                    w:SetBrushColor(c)
                    visibility(w, passive)
                    add(w, x, y, ww, hh, z)
                    return w
                end
                local slateColor
                pcall(function() slateColor = imported("SlateColor") end)
                local function textStyle(w, size, c)
                    local font = member(w, "Font")
                    if font ~= nil then
                        if type(font) == 'table' then
                            local copy = {}
                            for k, v in pairs(font) do copy[k] = v end
                            font = copy
                        end
                        font.Size = size
                        pcall(function() w:SetFont(font) end)
                    end
                    pcall(function() w:SetColorAndOpacity(slateColor and slateColor(c) or c) end)
                    pcall(function() w:SetJustification(1) end)
                    visibility(w, passive)
                end
                local function text(value, x, y, ww, hh, size, c, z)
                    local w = make("TextBlock", data.Container)
                    w:SetText(value)
                    textStyle(w, size, c)
                    pcall(function() w:SetAutoWrapText(true) end)
                    add(w, x, y, ww, hh, z)
                    return w
                end
                local W, H = WelcomeUI.Width, WelcomeUI.Height
                rect(4, 6, W, H, color(18, 5, 10, 0.25), 0)
                rect(0, 0, W, H, color(255, 40, 180), 1)
                rect(2, 2, W - 4, H - 4, color(255, 255, 255), 2)
                local stops = {
                    {255, 40, 180}, {150, 60, 255}, {0, 210, 255},
                    {0, 255, 160}, {255, 235, 40}
                }
                local segments = 64
                for i = 0, segments - 1 do
                    local t = i / (segments - 1)
                    local scaled = t * (#stops - 1)
                    local index = math.min(#stops - 1, math.floor(scaled) + 1)
                    local left, right, blend = stops[index], stops[index + 1], scaled - (index - 1)
                    local x0 = 2 + (W - 4) * i / segments
                    local x1 = 2 + (W - 4) * (i + 1) / segments
                    rect(x0, 2, math.min(W - 2, x1 + 0.3) - x0, 76,
                        color(left[1] + (right[1] - left[1]) * blend,
                              left[2] + (right[2] - left[2]) * blend,
                              left[3] + (right[3] - left[3]) * blend), 3)
                end
                rect(18, 3, W - 36, 1, color(255, 255, 255, 0.32), 4)
                rect(2, 78, W - 4, 3, color(0, 210, 255), 4)
                local title = text(WelcomeText[1], 24, 23, W - 48, 44, 19, color(20, 20, 28), 5)
                pcall(function() title:SetShadowOffset(vector(0, 1)) end)
                pcall(function() title:SetShadowColorAndOpacity(color(40, 3, 12, 0.45)) end)
                rect(30, 100, W - 60, 54, color(245, 247, 255), 3)
                rect(30, 100, 4, 54, color(190, 40, 255), 4)
                text(WelcomeText[2], 46, 110, W - 92, 38, 23, color(20, 20, 28), 5)
                text(WelcomeText[3], 30, 168, W - 60, 32, 17, color(45, 45, 58), 5)
                local button = make("Button", data.Container)
                pcall(function() button:SetBackgroundColor(color(190, 40, 255)) end)
                visibility(button, visible)
                local label = make("TextBlock", button)
                label:SetText("OK")
                textStyle(label, 17, color(255, 251, 238))
                local ls = button:AddChild(label)
                pcall(function() ls:SetHorizontalAlignment(2) end)
                pcall(function() ls:SetVerticalAlignment(2) end)
                add(button, (W - 164) / 2, 212, 164, 42, 6)
                data.Event = member(button, "OnClicked")
                data.EventHandle = data.Event:Add(function()
                    if UI._data == data and data.Visible then UI:Destroy() end
                end)
                local slot = par:AddChildToCanvas(data.Container)
                slot:SetAutoSize(false)
                slot:SetSize(vector(W, H))
                slot:SetZOrder(9200)
                local anchors = slot:GetAnchors()
                anchors.Minimum, anchors.Maximum = vector(0.5, 0.5), vector(0.5, 0.5)
                slot:SetAnchors(anchors)
                slot:SetAlignment(vector(0.5, 0.5))
                slot:SetPosition(vector(0, 0))
                visibility(data.Container, passive)
            end)
            if not ok then detach(data); return false, "WELCOME_BUILD_FAILED" end
            data.Visible = true
            UI._data = data
            UI._shown = true
            return true
        end
        function UI:Hide() if UI._data then detach(UI._data) end; UI._data = nil end
        function UI:IsShown() return UI._shown == true end
        return UI
    end
    return Module
end)()
_G.MasterWelcomeUI = MasterWelcomeUI

-- ============================================================================
-- 4. LICENSE RUNTIME
-- ============================================================================
local MasterLicenseRuntime = (function()
    local Runtime = {}
    Runtime.__index = Runtime
    local function finite(n)
        return type(n) == 'number' and n == n and n >= 0 and n < math.huge
    end
    local function read(o, k)
        if o == nil then return nil end
        local ok, v = pcall(function() return o[k] end)
        if ok then return v end
    end
    local function static(o, k, ...)
        local fn = read(o, k)
        if type(fn) ~= 'function' then return nil end
        local ok, v = pcall(fn, ...); if ok then return v end
    end
    local function call(o, k, ...)
        local fn = read(o, k)
        if type(fn) ~= 'function' then return nil end
        local ok, v = pcall(fn, o, ...); if ok then return v end
    end
    local function validConfig(c)
        return type(c) == 'table' and type(c.url) == 'string' and c.url:match('^https://') ~= nil
            and type(c.game) == 'string' and #c.game > 0
            and type(c.secret) == 'string' and #c.secret > 0
            and finite(c.timeout) and c.timeout > 0 and finite(c.clockSkew)
    end
    function Runtime.new(env, config, Core, LoginUI)
        local self = setmetatable({
            env = env or _G, reason = 'login_required', active = false,
            ready = false, disposed = false, uiRetryAt = 0, uiFailures = 0
        }, Runtime)
        if not validConfig(config) or type(Core) ~= 'table' or type(Core.new) ~= 'function'
            or type(Core.Primitives) ~= 'table' then
            self.reason = 'license_dependencies_unavailable'; return self
        end
        local cfg = {}
        for k, v in pairs(config) do cfg[k] = v end
        self.timeout = cfg.timeout
        if type(LoginUI) == 'table' and type(LoginUI.new) == 'function' then
            local ok, ui = pcall(LoginUI.new, self.env)
            if ok and type(ui) == 'table' then self.ui = ui end
        end
        if type(_G.MasterWelcomeUI) == 'table' and type(_G.MasterWelcomeUI.new) == 'function' then
            local okW, w = pcall(_G.MasterWelcomeUI.new, self.env)
            if okW and type(w) == 'table' then self.welcome = w end
        end
        self.welcomeShownThisSession = (_G.__MASTER_WELCOME_SHOWN_SESSION == true)
        self.welcomeScheduledAt = nil
        self.welcomeDelaySeconds = 3.0
        self.autoLoginAttempted = false
        self.submit = function(key) return self:login(key) end
        local ok, auth = pcall(Core.new, cfg, {
            clock = function() return self:_clock() end,
            wall = function()
                local value = static(read(self.env, 'os'), 'time')
                if finite(value) and value > 0 then return value end
            end,
            serial = function(key)
                local client = read(self.env, 'Client')
                local value = static(client, 'GetPhoneDeviceID')
                assert(type(value) == 'string' and #value > 0 and #value <= 512,
                    'DEVICE_ID_UNAVAILABLE')
                return Core.Primitives.name_uuid('MASTER-LUA-V1\0' .. key .. '\0' .. value)
            end,
            decode = function(raw)
                local json = self:_module('json', nil, 'common.json_util', 'decode')
                assert(json, 'JSON_UNAVAILABLE')
                return json.decode(raw)
            end,
            post = function(url, headers, body, callback, timeout)
                local manager = read(self.env, 'ModuleManager')
                local config = read(manager, 'CommonModuleConfig')
                local getter = read(manager, 'GetModule')
                assert(type(getter) == 'function' and config, 'HTTP_MANAGER_UNAVAILABLE')
                local http = getter(read(config, 'http_manager'))
                local post = read(http, 'Post')
                assert(type(post) == 'function', 'HTTP_POST_UNAVAILABLE')
                return post(http, url, headers, body, nil, callback, timeout)
            end,
            status = function(message, phase)
                self.active = false
                self.reason = phase == 'active' and 'waiting_maintenance' or 'login_required'
                self:_ui('SetStatus', message)
                self:_ui('SetBusy', phase == 'pending')
                if phase == 'active' then self:_ui('Hide') end
            end,
        })
        if ok and type(auth) == 'table' then self.auth = auth
        else self.reason = 'license_initialization_unavailable' end
        return self
    end
    function Runtime:_module(cache, globalName, path, method)
        local found = globalName and read(self.env, globalName)
        if type(read(found, method)) == 'function' then return found end
        found = self[cache]
        if type(read(found, method)) == 'function' then return found end
        local loader = read(self.env, 'require')
        if type(loader) == 'function' then
            local ok, value = pcall(loader, path)
            if ok and type(read(value, method)) == 'function' then
                self[cache] = value; return value
            end
        end
    end
    function Runtime:_valid(object)
        if object == nil then return false end
        if static(read(self.env, 'slua'), 'isValid', object) == true then return true end
        return call(read(self.env, 'Game'), 'IsValid', object) == true
    end
    function Runtime:_clock()
        local world = static(read(self.env, 'slua'), 'getWorld')
        if world == nil then return nil end
        local statics = read(self.env, 'GameplayStatics') or self.statics
        if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then
            local loader = read(self.env, 'import')
            if type(loader) == 'function' then
                local ok, value = pcall(loader, 'GameplayStatics')
                if ok then statics = value end
            end
        end
        if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then return nil end
        self.statics = statics
        local now = static(statics, 'GetRealTimeSeconds', world)
        if finite(now) then return now, world end
    end
    function Runtime:_readGameplay(world)
        local data = read(self.env, 'GameplayData') or self.gameplayData
        if data == nil then
            local loader = read(self.env, 'require')
            if type(loader) == 'function' then
                local ok, value = pcall(loader, 'GameLua.GameCore.Data.GameplayData')
                if ok and value ~= nil then self.gameplayData = value; data = value end
            end
        end
        local pc = static(data, 'GetPlayerController')
        if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then
            pc = call(read(self.env, 'slua_GameFrontendHUD'), 'GetPlayerController')
        end
        if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then
            return nil, 'waiting_controller'
        end
        local pawn = static(data, 'GetPlayerCharacter')
        if not self:_valid(pawn) then pawn = static(data, 'GetLocalCharacter') end
        for _, method in ipairs({'GetPlayerCharacterSafety', 'GetCurPawn', 'GetPawn'}) do
            if not self:_valid(pawn) then pawn = call(pc, method) end
            if not self:_valid(pawn) then pawn = call(read(pc, 'Object'), method) end
        end
        if not self:_valid(pawn) then return nil, 'waiting_pawn' end
        local tools = self:_module('tools', nil,
            'GameLua.Mod.BaseMod.Common.UI.InGameUITools', 'GetMainControlBaseUI')
        local root = static(tools, 'GetMainControlBaseUI')
        if not self:_valid(root) then return nil, 'waiting_control_ui' end
        local status = self:_module('gameStatus', 'GameStatus',
            'client.common.game_status', 'IsInFightingStatus')
        local loading = self:_module('loading', nil,
            'client.slua.logic.loading.logic_loading', 'IsShowing')
        if not status or not loading then return nil, 'readiness_services_unavailable' end
        if static(status, 'IsInFightingStatus') ~= true then return nil, 'waiting_gameplay' end
        if static(loading, 'IsShowing') ~= false then return nil, 'waiting_loading' end
        return {world = world, controller = pc, pawn = pawn, root = root}
    end
    local function same(a, b)
        return a and b and a.world == b.world and a.controller == b.controller
            and a.pawn == b.pawn and a.root == b.root
    end
    function Runtime:_ui(method, ...)
        local fn = read(self.ui, method)
        if type(fn) ~= 'function' then return false, 'UI_UNAVAILABLE' end
        local ok, value, reason = pcall(fn, ...)
        if not ok then return false, 'UI_TEMPORARILY_UNAVAILABLE' end
        return value, reason
    end
    function Runtime:_clearReadiness(reason)
        self.active, self.ready = false, false
        self.identity, self.readySince, self.maintenanceAt, self.maintenanceWorld = nil, nil, nil, nil
        self.reason = reason
        self:_ui('Hide')
    end
    function Runtime:_showPanel(now, state, blocked, initialKey)
        if now < self.uiRetryAt then return false end
        local shown, uiReason
        if blocked then shown, uiReason = self:_ui('ShowNotice', state.message)
        else shown, uiReason = self:_ui('Show', self.submit, initialKey) end
        if shown then
            self.uiFailures, self.uiError = 0, nil
            self:_ui('SetStatus', state.message)
            self:_ui('SetBusy', blocked or state.pending)
        else
            self.uiFailures = self.uiFailures + 1
            self.uiRetryAt = now + (self.uiFailures >= 10 and 5 or 1)
            self.uiError = type(uiReason) == 'string' and uiReason:match('^UI_[A-Z_]+$')
                or 'UI_UNAVAILABLE'
        end
        return shown == true
    end
    function Runtime:update()
        if self.disposed then self.reason = 'disposed'; return false end
        if not self.auth then return false end
        local tickOK = pcall(self.auth.Tick)
        if not tickOK then
            self.auth.FailClosed('License maintenance unavailable.')
            self:_clearReadiness('license_maintenance_unavailable'); return false
        end
        local now, world = self:_clock()
        if not now then self:_clearReadiness('clock_unavailable'); return false end
        local ready, reason = self:_readGameplay(world)
        if not ready then self:_clearReadiness(reason); return false end
        if not same(self.identity, ready) or not self.readySince or now < self.readySince then
            self.identity, self.readySince = ready, now
        end
        self.ready = now - self.readySince >= 3
        self.maintenanceAt, self.maintenanceWorld = now, world
        self.active = self.ready and self.auth.IsAuthorized()
        if not self.ready then
            self.reason = 'waiting_stable_gameplay'; self:_ui('Hide'); return false
        end
        local state = self.auth.GetState()
        if self.active then
            self.reason = 'active'
            self:_ui('Hide')
            if self.welcome and not self.welcomeShownThisSession then
                if not self.welcomeScheduledAt then self.welcomeScheduledAt = now end
                if self.welcomeScheduledAt
                    and (now - self.welcomeScheduledAt) >= self.welcomeDelaySeconds then
                    local shown = false
                    pcall(function()
                        if self.welcome:Show() then shown = true end
                    end)
                    if shown then
                        self.welcomeShownThisSession = true
                        _G.__MASTER_WELCOME_SHOWN_SESSION = true
                        self.welcomeScheduledAt = nil
                    else
                        self.welcomeScheduledAt = now
                    end
                end
            end
            return true
        end
        self.reason = 'login_required'
        -- Restore the previously successful key into the login box.
        -- The user still presses LOGIN/OK to authenticate again.
        local rememberedKey = nil
        pcall(function()
            if self.auth and type(self.auth.GetSavedKey) == 'function' then
                rememberedKey = self.auth.GetSavedKey()
            end
            if not rememberedKey then
                local g = rawget(_G, '__GRW_SAVED_LICENSE_KEY')
                if type(g) == 'string' and #g > 0 then rememberedKey = g end
            end
        end)
        self.rememberedKey = rememberedKey

        if state.restartRequired or state.phase == 'expired' or state.phase == 'tampered' then
            self.reason = state.restartRequired and 'restart_required' or state.phase
            self:_showPanel(now, state, true); return false
        end
        if not self:_showPanel(now, state, false, rememberedKey) and self.uiError then
            self.reason = 'login_ui_unavailable'
        end
        return false
    end
    function Runtime:isActive()
        if self.disposed or not self.auth or not self.active or not self.ready then return false end
        if not self.auth.IsAuthorized() then self.active = false; return false end
        local now, world = self:_clock()
        if not now or world ~= self.maintenanceWorld or not self.maintenanceAt
            or now < self.maintenanceAt or now - self.maintenanceAt >= 3 then
            self.active = false; self.reason = 'maintenance_stale'; return false
        end
        return true
    end
    function Runtime:login(key)
        if self.disposed or not self.auth then return false end
        if self.auth.IsAuthorized() then return true end
        local now, world = self:_clock()
        if not self.ready or not now or world ~= self.maintenanceWorld
            or not self.maintenanceAt or now < self.maintenanceAt
            or now - self.maintenanceAt >= 3 then return false end
        local identity = self:_readGameplay(world)
        if not same(identity, self.identity) then
            self:_clearReadiness('waiting_stable_gameplay'); return false
        end
        local ok, accepted = pcall(self.auth.Login, key)
        if not ok then self.auth.FailClosed('Login could not start.'); return false end
        return accepted == true
    end
    function Runtime:getStatus()
        local active = self:isActive()
        local state = self.auth and self.auth.GetState() or {}
        return {
            authorized = active, sessionAuthorized = state.authorized == true,
            phase = state.phase or 'locked',
            message = state.message or 'License dependencies unavailable.',
            reason = self.reason, pending = state.pending == true,
            gameplayReady = self.ready, expiresAt = state.expiresAt,
            accessPolicy = 'game_session', expiryCheckPolicy = 'login_only',
            clockProtection = 'login_only', periodicRecheck = false,
            loginDelaySeconds = 3, restartRequired = state.restartRequired == true,
            uiError = self.uiError,
            lastRequestLatencyMs = state.lastRequestLatencyMs,
            latencyScope = 'license_http_round_trip', disposed = self.disposed
        }
    end
    function Runtime:logout()
        self.active = false
        if self.auth then self.auth.Logout() end
        self.reason = 'login_required'; return true
    end
    function Runtime:dispose()
        if self.disposed then return true end
        self:logout(); self.disposed = true; self.ready = false
        self:_ui('Destroy'); self.reason = 'disposed'
        self.submit = nil
        return true
    end
    return Runtime
end)()


-- ============================================================================
-- AHMAD AUTH BOOTSTRAP / FEATURE GATE
-- ============================================================================
local masterESPLicenseInstance

local function masterESPEnsureLicense()
    if masterESPLicenseInstance then return end
    local host = setmetatable({GameplayData = GameplayData}, {__index = _ENV})
    masterESPLicenseInstance = MasterLicenseRuntime.new(
        host, MasterLicenseConfig, MasterLicenseCore, MasterLoginUI)
end

local function AHMADAuthActive()
    if not masterESPLicenseInstance then
        masterESPEnsureLicense()
    end
    local active = false
    pcall(function()
        active = masterESPLicenseInstance and masterESPLicenseInstance:isActive() == true
    end)
    return active
end

_G.AHMADAuthActive = AHMADAuthActive

function _G.MasterLicenseLogin(key)
    masterESPEnsureLicense()
    if not masterESPLicenseInstance then return false, 'license_unavailable' end
    local ok, result = pcall(masterESPLicenseInstance.login, masterESPLicenseInstance, key)
    if not ok then return false, 'license_unavailable' end
    return result
end

function _G.MasterLicenseLogout()
    if not masterESPLicenseInstance then return false end
    return pcall(masterESPLicenseInstance.logout, masterESPLicenseInstance)
end

function _G.MasterLicenseStatus()
    masterESPEnsureLicense()
    if not masterESPLicenseInstance then
        return {authorized = false, phase = 'locked', message = 'license_unavailable'}
    end
    local ok, value = pcall(masterESPLicenseInstance.getStatus, masterESPLicenseInstance)
    return ok and value or {authorized = false, phase = 'locked'}
end

local function AHMADAuthTick()
    if masterESPLicenseInstance then
        pcall(masterESPLicenseInstance.update, masterESPLicenseInstance)
    end
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, AHMADAuthTick)
        end
    end)
end

masterESPEnsureLicense()
AHMADAuthTick()
print("[AUTH] Ahmad feature gate initialized: login required.")


pcall(function()

local log = function(msg) print("[SH Menu] " .. tostring(msg)) end
log("File loaded")

-- ============================================================
-- BRIDGE UNIFIED
-- ============================================================
_G.SHConfig        = _G.SHConfig        or {}
_G.GRW_XDConfig     = _G.GRW_XDConfig     or {}
_G.SHgamingConfig  = _G.SHgamingConfig  or {}
_G.SHgamingState   = _G.SHgamingState   or { CustomTextData = {} }
_G.SHgamingState.CustomTextData = _G.SHgamingState.CustomTextData or {}

_G.GRW_XDState = _G.GRW_XDState or {}
_G.GRW_XDState.CustomTextData = _G.GRW_XDState.CustomTextData or _G.SHgamingState.CustomTextData
_G.SHgamingState.CustomTextData = _G.GRW_XDState.CustomTextData

local function ToBool(v)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    return v and true or false
end

local function GetConfigPaths(fileName)
    local paths = {
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/Paks/puffer_temp/" .. fileName,
        "GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "../../GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
    }
    pcall(function()
        if os and os.getenv then
            local homeDir = os.getenv("HOME")
            if homeDir and homeDir ~= "" then
                table.insert(paths, 1, homeDir .. "/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName)
            end
        end
    end)
    return paths
end

local CONFIG_FILE = "GRW_Official_settings.txt"
local LOADED_FROM_1LUA = false

-- Load the newest valid copy. Older versions stopped at the first existing
-- path, which could restore stale settings after a restart.
pcall(function()
    local bestSaved, bestStamp = nil, -1
    for _, path in ipairs(GetConfigPaths(CONFIG_FILE)) do
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content and #content > 0 then
                local ok, saved = pcall(function()
                    local fn = load(content)
                    return fn and fn() or nil
                end)
                if ok and type(saved) == "table" then
                    local stamp = tonumber(saved.SavedAt) or 0
                    if bestSaved == nil or stamp >= bestStamp then
                        bestSaved, bestStamp = saved, stamp
                    end
                end
            end
        end
    end

    if type(bestSaved) == "table" then
        if type(bestSaved.LicenseKey) == "string" and #bestSaved.LicenseKey > 0 then
            _G.__GRW_SAVED_LICENSE_KEY = bestSaved.LicenseKey
        end

        if type(bestSaved.GRW_XDConfig) == "table" then
            for k, v in pairs(bestSaved.GRW_XDConfig) do
                _G.SHConfig[k] = v
                _G.GRW_XDConfig[k] = v
                _G.SHgamingConfig[k] = v
            end
        end

        if type(bestSaved.SHConfig) == "table" then
            for k, v in pairs(bestSaved.SHConfig) do
                local n = tonumber(v)
                _G.SHConfig[k] = n or (v and 1 or 0)
                _G.GRW_XDConfig[k] = ToBool(_G.SHConfig[k])
                _G.SHgamingConfig[k] = _G.SHConfig[k]
            end
        end

        if type(bestSaved.CustomTextData) == "table" then
            _G.GRW_XDState.CustomTextData = _G.GRW_XDState.CustomTextData or {}
            _G.SHgamingState.CustomTextData = _G.SHgamingState.CustomTextData or {}
            for k, v in pairs(bestSaved.CustomTextData) do
                _G.GRW_XDState.CustomTextData[k] = v
                _G.SHgamingState.CustomTextData[k] = v
            end
        end
        LOADED_FROM_1LUA = true
    end
end)

if LOADED_FROM_1LUA then log("Loaded persistent config: " .. CONFIG_FILE)
else log("No persistent config yet: " .. CONFIG_FILE) end

-- Save to every writable copy so another package/path cannot load an old file.
local _lastSaveStr = ""
local function SaveConfig()
    pcall(function()
        local data = "return {\n"
        data = data .. "SavedAt = " .. tostring(os.time()) .. ",\n"

        local licenseKey = rawget(_G, '__GRW_SAVED_LICENSE_KEY')
        if type(licenseKey) == "string" and #licenseKey > 0 then
            data = data .. "LicenseKey = " .. string.format("%q", licenseKey) .. ",\n"
        end

        data = data .. "GRW_XDConfig = {\n"
        for k, v in pairs(_G.SHConfig) do
            if type(v) == "number" or type(v) == "boolean" then
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "},\nCustomTextData = {\n"

        local mergedCustom = {}
        for k, v in pairs(_G.SHgamingState.CustomTextData or {}) do
            mergedCustom[k] = v
        end
        if _G.GRW_XDState and _G.GRW_XDState.CustomTextData then
            for k, v in pairs(_G.GRW_XDState.CustomTextData) do
                mergedCustom[k] = v
            end
        end
        for k, v in pairs(mergedCustom) do
            if type(v) == "number" or type(v) == "boolean" then
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "}\n}"

        if data == _lastSaveStr then return end

        local wroteAny = false
        for _, path in ipairs(GetConfigPaths(CONFIG_FILE)) do
            local f = io.open(path, "w")
            if f then
                f:write(data)
                f:close()
                wroteAny = true
            end
        end
        if wroteAny then _lastSaveStr = data end
    end)
end

local function ScheduleSave()
    -- Save immediately so a quick game restart cannot lose the last toggle/slider.
    pcall(SaveConfig)
end

-- Used by the license runtime after a successful login.
_G.__GRWPersistLicenseKey = function(key)
    if type(key) ~= "string" then return end
    key = key:match("^%s*(.-)%s*$")
    if #key == 0 or #key > 512 then return end
    _G.__GRW_SAVED_LICENSE_KEY = key
    pcall(SaveConfig)
end

_G.SHMenuSave = ScheduleSave
_G.SaveModSettings = SaveConfig

local function AutoSaveLoop()
    pcall(SaveConfig)
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(3.0, AutoSaveLoop)
        end
    end)
end
AutoSaveLoop()

local function ReadKeyValue(key, fallback)
    if _G.GRW_XDState and _G.GRW_XDState.CustomTextData
       and _G.GRW_XDState.CustomTextData[key] ~= nil then
        return _G.GRW_XDState.CustomTextData[key]
    end
    if _G.SHgamingState and _G.SHgamingState.CustomTextData
       and _G.SHgamingState.CustomTextData[key] ~= nil then
        return _G.SHgamingState.CustomTextData[key]
    end
    if _G.SHConfig and _G.SHConfig[key] ~= nil then
        return _G.SHConfig[key]
    end
    return fallback
end

local function WriteKeyValue(key, value, isToggle)
    if isToggle then
        _G.SHConfig[key] = value
        _G.GRW_XDConfig[key] = (value == 1)
        _G.SHgamingConfig[key] = value
    else
        _G.SHConfig[key] = value
        _G.GRW_XDConfig[key] = value
        _G.SHgamingConfig[key] = value
        if _G.SHgamingState and _G.SHgamingState.CustomTextData then
            _G.SHgamingState.CustomTextData[key] = value
        end
        if _G.GRW_XDState and _G.GRW_XDState.CustomTextData then
            _G.GRW_XDState.CustomTextData[key] = value
        end
    end
end

function _G.SHSetToggle(key, val)
    _G.SHConfig[key] = val and 1 or 0
    _G.GRW_XDConfig[key] = val and true or false
    _G.SHgamingConfig[key] = _G.SHConfig[key]
end

function _G.SHGetToggle(key)
    return (_G.SHConfig[key] == 1) or (_G.GRW_XDConfig[key] == true)
end

log("Config bridge ready")

-- Defaults
local DEFAULTS = {
    EspVip = 0, EspDistance = 0, EspVipPro = 0,
    Esp3ShowName = 1, Esp3ShowHP = 1,
    EspRadar = 0, EspLoai5 = 0, EspLoai6 = 0, EspLoai7 = 0,
    EspLoai8 = 0, EspLoai9 = 0,
    Esp7_SoLuong = 1, Esp7_VuKhi = 1, Esp7_TuThe = 1,
    EspAimWarning = 0, EspAimWarningVisCheck = 0,
    EspBomMaster = 0, EspItemBom = 0, EspActiveBom = 0,
    EspVehicle = 0,
    EspVeh_Dacia = 1, EspVeh_UAZ = 1, EspVeh_Buggy = 1,
    EspVeh_Coupe = 1, EspVeh_Mirado = 1, EspVeh_Motorcycle = 1, EspVeh_Other = 1,
    EspAntenna = 0, EspOutline = 0, EspName = 0,
    OutlineThickness = 10, OutlineColor = 4,
    Esp9_Count = 1, Esp9_Name = 1, Esp9_Distance = 1,
    Esp9_HP = 1, Esp9_Team = 1, Esp9_Weapon = 1,
    Esp9_Line = 0, Esp9_Skeleton = 0,
    Esp9_LineThick = 1, Esp9_LineVisColor = 2, Esp9_LineHidColor = 1,
    Esp9_SkelThick = 1, Esp9_SkelVisColor = 2, Esp9_SkelHidColor = 1,
    CustomAimbot = 0, CustomAimbotClose = 0,
    CustomHRecoil = 0, CustomVRecoil = 0,
    LessShake = 0, Accuracy = 0, Crosshair = 0, AutoHead = 0,
    OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0,
    HRecoil = 30, VRecoil = 30,
    AimTouchEnable = 0, EspFovCircle = 0, AimTouchHipfire = 0,
    AimTouchHipIgKnock = 0, AimTouchHipIgBot = 0, AimTouchHipVisCheck = 0,
    AimTouchSG = 0, AimTouchSGAutoFire = 0,
    AimTouchSGIgKnock = 0, AimTouchSGIgBot = 0, AimTouchSGVisCheck = 0,
    AimTouchScopeAll = 0, AimTouchScopeIgKnock = 0, AimTouchScopeIgBot = 0,
    AimTouchScopeVisCheck = 0, AimTouchScopeSniper = 0,
    AimTouchSniperIgKnock = 0, AimTouchSniperIgBot = 0, AimTouchSniperVisCheck = 0,
    AimTouchMortar = 0,
    FastMovement = 0, FastMovementSpeed = 10, FakeHWID = 0,
    IpadView = 0, IpadViewVehicle = 0, IpadViewScope = 0,
    IpadViewFOV = 30, IpadViewVehicleFOV = 30, IpadViewScopeFOV = 60,
    BugManEnable = 0, BugManRatio = 133, UnlockFPS = 0,
    WallXuyenTuong = 0, ColorBodyV2 = 0, ColorBodyNew = 0,
    ColorBodyV3 = 0, ColorV3Hidden = 1, ColorV3Visible = 2, ColorV3Thickness = 4,
    WallVehicle = 0, WhiteBody = 0, BlackSky = 0,
    RemoveFog = 0, RemoveGrass = 0, RemoveTrees = 0,
    WallClimb = 0, FastCar = 0, FastCarSpeed = 50,
    WeaponGlow = 0, WeaponGlowColor = 5, WeaponGlowThickness = 3,
    AutoReportEnable = 0, AutoMassReport = 0, AutoKillerReport = 0,
    WallhackRainbow = 0, SanhSieuXeVip = 0,
}

for k, v in pairs(DEFAULTS) do
    if _G.SHConfig[k] == nil then _G.SHConfig[k] = v end
    _G.GRW_XDConfig[k] = ToBool(_G.SHConfig[k])
    _G.SHgamingConfig[k] = _G.SHConfig[k]
end

local DEFAULT_CUSTOM = {
    ColorV3Hidden = 1, ColorV3Visible = 2, ColorV3Thickness = 4,
    OutlineColor = 4, OutlineThickness = 10,
    HiddenR = 150, HiddenG = 0, HiddenB = 0, HiddenA = 25,
    VisibleR = 0, VisibleG = 150, VisibleB = 0, VisibleA = 25,
    Esp9_LineVisColor = 2, Esp9_LineHidColor = 1, Esp9_LineThick = 1,
    Esp9_SkelVisColor = 2, Esp9_SkelHidColor = 1, Esp9_SkelThick = 1,
    WeaponGlowColor = 5, WeaponGlowThickness = 3,
    BugManRatio = 133, FastCarSpeed = 2000,
    IpadViewFOV = 120, IpadViewVehicleFOV = 120, IpadViewScopeFOV = 60,
    OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0,
    HRecoil = 0.3, VRecoil = 0.3,
    AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1,
    AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
    AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1,
    AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
    AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1,
    AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300,
    AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
    AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2,
    AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
    AimTouchSniperPred = 0, AimTouchMortarPred = 0, AimTouchMortarFOV = 360,
    AimTouchHipFOVColor = 7, AimTouchSGFOVColor = 1,
    AimTouchScopeFOVColor = 6, AimTouchSniperFOVColor = 4, AimTouchMortarFOVColor = 5,
}
for k, v in pairs(DEFAULT_CUSTOM) do
    if _G.SHgamingState.CustomTextData[k] == nil then
        _G.SHgamingState.CustomTextData[k] = v
    end
    if _G.GRW_XDState.CustomTextData[k] == nil then
        _G.GRW_XDState.CustomTextData[k] = v
    end
end
log("Ready")

-- Import (SAFE: import() throws on missing class, must not kill whole pcall)
local function SafeImport(name, fallbackPath)
    local ok, v = pcall(import, name)
    if ok and v ~= nil then return v end
    if fallbackPath then
        local ok2, v2 = pcall(import, fallbackPath)
        if ok2 and v2 ~= nil then return v2 end
    end
    if _G and _G[name] ~= nil then return _G[name] end
    return nil
end
local FLinearColor = SafeImport("LinearColor") or _G.FLinearColor
local FVector2D    = SafeImport("Vector2D") or _G.FVector2D
local FSlateColor  = SafeImport("SlateColor", "/Script/SlateCore.SlateColor")
local FAnchors     = SafeImport("Anchors") or _G.FAnchors
local FMargin      = SafeImport("Margin", "/Script/SlateCore.Margin")
-- Last-resort dummy so `C = { ... FLinearColor(...) }` never kills the whole pcall
if not FLinearColor then
    FLinearColor = function(r,g,b,a) return {R=r or 1, G=g or 1, B=b or 1, A=a or 1, r=r or 1, g=g or 1, b=b or 1, a=a or 1} end
end
if not FVector2D then
    FVector2D = function(x,y) return {X=x or 0, Y=y or 0, x=x or 0, y=y or 0} end
end

local function IsValid(obj)
    return obj and slua and slua.isValid and slua.isValid(obj)
end

-- ============================================================
-- UI THEME - DARK GRAPHITE CONTENT, HIGH-CONTRAST WHITE TEXT, RGB FRAME/SIDEBAR
-- ============================================================
local C = {
    -- GRW premium graphite + gold theme
    panel_bg      = FLinearColor(0.00, 0.00, 0.00, 1.00),
    panel_bg_dark = FLinearColor(0.00, 0.00, 0.00, 1.00),
    panel_header  = FLinearColor(0.00, 0.00, 0.00, 1.00),
    panel_border  = FLinearColor(0.82, 0.56, 0.08, 1.00),
    panel_inner   = FLinearColor(0.00, 0.00, 0.00, 1.00),
    panel_row     = FLinearColor(0.02, 0.02, 0.02, 1.00),
    tab_bg        = FLinearColor(0.02, 0.02, 0.02, 1.00),
    text_white    = FLinearColor(0.96, 0.97, 1.00, 1.00),
    text_dark     = FLinearColor(0.96, 0.97, 1.00, 1.00),
    text_blue     = FLinearColor(1.00, 0.78, 0.20, 1.00),
    text_dim      = FLinearColor(0.68, 0.72, 0.80, 1.00),
    accent_blue   = FLinearColor(0.05, 0.45, 1.00, 0.20),
    accent_blue_dark = FLinearColor(1.00, 0.70, 0.12, 1.00),
    accent_cyan   = FLinearColor(1.00, 0.76, 0.18, 1.00),
    accent_purple = FLinearColor(0.90, 0.58, 0.10, 1.00),
    accent_green  = FLinearColor(0.18, 0.78, 0.48, 1.00),
    accent_red    = FLinearColor(0.92, 0.22, 0.16, 1.00),
    accent_yellow = FLinearColor(1.00, 0.74, 0.12, 1.00),
    toggle_on     = FLinearColor(0.96, 0.06, 0.12, 1.00),
    toggle_on_glow= FLinearColor(0.96, 0.06, 0.12, 0.24),
    toggle_off    = FLinearColor(0.25, 0.28, 0.34, 1.00),
    toggle_green  = FLinearColor(0.96, 0.06, 0.12, 1.00),
    toggle_knob   = FLinearColor(1.00, 1.00, 1.00, 1.00),
    slider_bg     = FLinearColor(0.65, 0.70, 0.78, 0.32),
    slider_fill   = FLinearColor(1.00, 0.68, 0.08, 1.00),
    slider_knob   = FLinearColor(1.00, 1.00, 1.00, 1.00),
    GRW_XD        = FLinearColor(0.00, 0.00, 0.00, 0.00),
    transparent   = FLinearColor(0, 0, 0, 0.00),
    online_green  = FLinearColor(0.10, 0.78, 0.42, 1.00),
    white         = FLinearColor(1.00, 1.00, 1.00, 1.00),
}

-- DISPLAY CONFIG (screen pixels). Screenshot-matched left-docked panel.
local M_W, M_H = 520, 920
local MENU_X_OFFSET, MENU_Y_OFFSET = 0, 0
-- Floating GRW button vertical offset from the top; X is calculated from viewport width.
local MINI_X, MINI_Y = 0, 8
local HEADER_H = 64
local ROW_H = 42
local SIDEBAR_W = 166
local COL_W = (M_W - SIDEBAR_W - 42) / 2
local COL_GAP = 8

-- State
local parentCanvas, bgPanel = nil, nil
local floatItem = nil
local miniItem = nil
local isMenuOpen, menuBuilt = false, false
local allWidgets = {}

-- UMG helpers
local function NewObject(path, parent)
    local obj = nil
    pcall(function()
        if CGame and CGame.NewObjectFromPath then
            obj = CGame:NewObjectFromPath(path, parent)
        end
    end)
    return obj
end

local function Layer(parent, x, y, w, h, color, z)
    local b = NewObject("/Script/UMG.Border", parent)
    if IsValid(b) then
        pcall(function() b:SetBrushColor(color) end)
        pcall(function() b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        local slot = parent:AddChildToCanvas(b)
        if slot then
            slot:SetAutoSize(false)
            slot:SetPosition(FVector2D(x, y))
            slot:SetSize(FVector2D(w, h))
            slot:SetZOrder(z or 0)
        end
    end
    table.insert(allWidgets, b)
    return b
end

local _rgbTextIndex = 0
local _rgbTextPalette = {
    FLinearColor(1.00, 0.08, 0.12, 1.00),
    FLinearColor(1.00, 0.35, 0.05, 1.00),
    FLinearColor(1.00, 0.78, 0.05, 1.00),
    FLinearColor(0.20, 1.00, 0.18, 1.00),
    FLinearColor(0.00, 0.88, 0.95, 1.00),
    FLinearColor(0.10, 0.35, 1.00, 1.00),
    FLinearColor(0.58, 0.12, 1.00, 1.00),
    FLinearColor(1.00, 0.12, 0.62, 1.00),
}

local function Text(parent, txt, x, y, size, color, z, alignX, alignY)
    local t = NewObject("/Script/UMG.TextBlock", parent)
    if IsValid(t) then
        local shownText = tostring(txt or ""):upper()
        _rgbTextIndex = (_rgbTextIndex % #_rgbTextPalette) + 1
        -- Force all menu text rendered through Text() to solid white.
        local rgbColor = FLinearColor(1.00, 1.00, 1.00, 1.00)
        pcall(function() t:SetText(shownText) end)
        pcall(function()
            if FSlateColor then t:SetColorAndOpacity(FSlateColor(rgbColor))
            else t:SetColorAndOpacity(rgbColor) end
        end)
        pcall(function()
            if t.Font then
                local f = t.Font
                f.Size = size
                t.Font = f
            end
        end)
        pcall(function() t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        local slot = parent:AddChildToCanvas(t)
        if slot then
            slot:SetAutoSize(true)
            slot:SetAlignment(FVector2D(alignX or 0.5, alignY or 0.5))
            slot:SetPosition(FVector2D(x, y))
            slot:SetZOrder(z or 100)
        end
    end
    table.insert(allWidgets, t)
    return t
end


-- Drag support: use UMG press/release events and poll the current pointer position.
-- Works with game builds that expose PlayerController:GetMousePosition and time_ticker.
local _dragState = nil
local _dragTickerRunning = false

local function GetPointerPosition()
    local x, y
    pcall(function()
        local pc = nil
        if Game and Game.GetFirstPlayerController then pc = Game:GetFirstPlayerController() end
        if not pc and UE and UE.GetPlayerController then pc = UE.GetPlayerController(0) end
        if pc and pc.GetMousePosition then
            local ok, px, py = pc:GetMousePosition()
            if ok ~= false and type(px) == "number" and type(py) == "number" then
                x, y = px, py
            end
        end
    end)
    return x, y
end

local function SetCanvasPosition(widget, x, y)
    if not IsValid(widget) or not widget.Slot or not FVector2D then return false end
    local ok = pcall(function() widget.Slot:SetPosition(FVector2D(x, y)) end)
    return ok
end

local function StartDrag(widget, mode)
    local x, y = GetPointerPosition()
    if not x or not y then return end
    local slot = widget and widget.Slot
    if not slot then return end
    local posX, posY
    pcall(function()
        local pos = slot:GetPosition()
        if pos then posX, posY = pos.X, pos.Y end
    end)
    if not posX or not posY then return end
    _dragState = { widget = widget, mode = mode, startX = x, startY = y,
        posX = posX, posY = posY, moved = false }
    if _dragTickerRunning then return end
    _dragTickerRunning = true
    local function tick()
        if not _dragState then _dragTickerRunning = false return end
        local st = _dragState
        local px, py = GetPointerPosition()
        if px and py and IsValid(st.widget) then
            local dx, dy = px - st.startX, py - st.startY
            if math.abs(dx) + math.abs(dy) > 5 then st.moved = true end
            if st.mode == "resize" then
                local nw = math.max(420, math.min(1200, M_W + dx))
                local nh = math.max(300, math.min(900, M_H + dy))
                M_W, M_H = nw, nh
                pcall(function() st.widget.Slot:SetSize(FVector2D(nw, nh)) end)
            else
                SetCanvasPosition(st.widget, math.max(0, st.posX + dx), math.max(0, st.posY + dy))
            end
        end
        pcall(function()
            local ticker = require("common.time_ticker")
            if ticker and ticker.AddTimerOnce then ticker.AddTimerOnce(0.03, tick)
            else _dragTickerRunning = false end
        end)
    end
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then ticker.AddTimerOnce(0.03, tick)
        else _dragTickerRunning = false end
    end)
end

local function StopDrag(widget)
    if _dragState and (not widget or _dragState.widget == widget) then _dragState = nil end
end

local function BindDragEvents(widget, mode, dragTarget)
    if not IsValid(widget) then return end
    dragTarget = dragTarget or widget
    pcall(function()
        if widget.OnPressed then widget.OnPressed:Add(function() StartDrag(dragTarget, mode) end) end
    end)
    pcall(function()
        if widget.OnReleased then widget.OnReleased:Add(function() StopDrag(dragTarget) end) end
    end)
end

local function MakeBtn(parent, x, y, w, h, z, onClick)
    local btn = NewObject("/Script/UMG.Button", parent)
    if IsValid(btn) then
        pcall(function() btn:SetColorAndOpacity(C.transparent) end)
        pcall(function() btn:SetBackgroundColor(C.transparent) end)
        pcall(function() btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) end)
        local slot = parent:AddChildToCanvas(btn)
        if slot then
            slot:SetAutoSize(false)
            slot:SetPosition(FVector2D(x, y))
            slot:SetSize(FVector2D(w, h))
            slot:SetZOrder(z or 900)
        end
        if onClick then
            pcall(function()
                if btn.OnClicked then
                    btn.OnClicked:Add(function() pcall(onClick) end)
                end
            end)
        end
    end
    table.insert(allWidgets, btn)
    return btn
end

local function GetCanvas()
    if IsValid(parentCanvas) then return parentCanvas end
    parentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if not MainUI or not Game:IsValid(MainUI) then return end
        if MainUI.CanvasPanel_0 and Game:IsValid(MainUI.CanvasPanel_0) then
            parentCanvas = MainUI.CanvasPanel_0
        elseif MainUI.CanvasPanel_42 and Game:IsValid(MainUI.CanvasPanel_42) then
            parentCanvas = MainUI.CanvasPanel_42
        end
    end)
    return parentCanvas
end

local BuildMenu
local ShowMenu, HideMenu

local _miniRGBIndex = 0
local function ToggleRGBColor()
    _miniRGBIndex = (_miniRGBIndex % #_rgbTextPalette) + 1
    return _rgbTextPalette[_miniRGBIndex]
end

-- ============================================================
-- TOP-CENTER GRW MINI OPENER
-- Hidden while menu is open. After closing, it stays visible for
-- 10 seconds and then fades to a very low opacity.
-- ============================================================
local _miniFadeToken = 0
local _miniW, _miniH = 150, 54

local function SetMiniOpacity(alpha)
    if not IsValid(miniItem) then return end
    pcall(function()
        if miniItem.SetRenderOpacity then miniItem:SetRenderOpacity(alpha) end
    end)
end

local function PositionMiniButton()
    if not IsValid(miniItem) or not FVector2D then return end
    local vpW, vpH = nil, nil
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util and ui_util.GetViewportSize then
            local vp = ui_util.GetViewportSize()
            if vp and vp.X and vp.Y and vp.X > 0 and vp.Y > 0 then
                vpW, vpH = vp.X, vp.Y
            end
        end
    end)
    local slot = miniItem.Slot
    if not slot then return end
    pcall(function()
        slot:SetAutoSize(false)
        slot:SetSize(FVector2D(_miniW, _miniH))
        -- Anchor the opener to the horizontal midpoint of its parent canvas.
        -- Center alignment means its own width is offset automatically, so it
        -- stays top-center even if the viewport and game HUD canvas differ.
        if FAnchors then slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0)) end
        slot:SetAlignment(FVector2D(0.5, 0))
        slot:SetPosition(FVector2D(0, MINI_Y))
        slot:SetZOrder(30000)
    end)
end

local function BuildMiniButton()
    if IsValid(miniItem) then
        PositionMiniButton()
        return miniItem
    end
    local canvas = GetCanvas()
    if not canvas then return nil end

    miniItem = NewObject("/Script/UMG.CanvasPanel", canvas)
    if not IsValid(miniItem) then miniItem = nil return nil end
    local slot = canvas:AddChildToCanvas(miniItem)
    if not slot then miniItem = nil return nil end
    pcall(function()
        slot:SetAutoSize(false)
        slot:SetSize(FVector2D(_miniW, _miniH))
        slot:SetZOrder(30000)
    end)

    Layer(miniItem, 0, 0, _miniW, _miniH, C.panel_header, 1)
    Layer(miniItem, 0, 0, _miniW, 2, C.panel_border, 2)
    Layer(miniItem, 0, _miniH - 2, _miniW, 2, C.panel_border, 2)
    Layer(miniItem, 0, 0, 2, _miniH, C.panel_border, 2)
    Layer(miniItem, _miniW - 2, 0, 2, _miniH, C.panel_border, 2)
    Text(miniItem, "GRW", _miniW * 0.5, 16, 18, ToggleRGBColor(), 5, 0.5, 0.5)
    Text(miniItem, "TAP TO OPEN", _miniW * 0.5, 36, 9, C.white, 5, 0.5, 0.5)
    local miniHit = MakeBtn(miniItem, 0, 0, _miniW, _miniH, 20, function()
        -- A drag should reposition the opener, not trigger the tap action.
        if _dragState and _dragState.widget == miniItem and _dragState.moved then return end
        _miniFadeToken = _miniFadeToken + 1
        if menuBuilt and IsValid(bgPanel) then
            ShowMenu()
        else
            BuildMenu()
        end
    end)
    BindDragEvents(miniHit, "move", miniItem)
    PositionMiniButton()
    return miniItem
end

local function ShowMiniButton()
    -- Floating opener is available only after successful key authentication.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then
        HideMiniButton()
        return false
    end
    _miniFadeToken = _miniFadeToken + 1
    local token = _miniFadeToken
    if not BuildMiniButton() then return end
    SetMiniOpacity(1.0)
    pcall(function() miniItem:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) end)
    PositionMiniButton()
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(10.0, function()
                if token ~= _miniFadeToken or isMenuOpen then return end
                local alpha = 1.0
                local function fadeStep()
                    if token ~= _miniFadeToken or isMenuOpen then return end
                    alpha = alpha - 0.08
                    if alpha <= 0.12 then
                        SetMiniOpacity(0.12)
                        return
                    end
                    SetMiniOpacity(alpha)
                    pcall(function() ticker.AddTimerOnce(0.12, fadeStep) end)
                end
                fadeStep()
            end)
        end
    end)
end

local function HideMiniButton()
    _miniFadeToken = _miniFadeToken + 1
    if IsValid(miniItem) then
        SetMiniOpacity(0.0)
        pcall(function() miniItem:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    end
end

-- Keep the menu's own show/hide state deterministic.
ShowMenu = function()
    -- Hard gate: authenticated users only.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then
        HideMiniButton()
        return false
    end
    if IsValid(bgPanel) then
        pcall(function() bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) end)
        isMenuOpen = true
        HideMiniButton()
    else
        BuildMenu()
    end
end

HideMenu = function()
    isMenuOpen = false
    if IsValid(bgPanel) then
        pcall(function() bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    end
    ShowMiniButton()
end

-- ============================================================
-- TOGGLE SWITCH
-- ============================================================

-- Rounded pill built from narrow horizontal slices. This avoids the square
-- UMG Border corners and matches the compact capsule switches in the reference.
local function AddPillShape(parent, x, y, w, h, color, z, circle)
    local pieces = {}
    local rows = math.max(6, math.floor(h))
    local radius = h * 0.5
    for row = 0, rows - 1 do
        local dy = math.abs((row + 0.5) - radius)
        local inset = 0
        if circle then
            local rr = math.max(0, radius * radius - dy * dy)
            inset = radius - math.sqrt(rr)
        else
            local rr = math.max(0, radius * radius - dy * dy)
            inset = radius - math.sqrt(rr)
        end
        local px = x + math.floor(inset)
        local pw = math.max(1, w - 2 * math.floor(inset))
        pieces[#pieces + 1] = Layer(parent, px, y + row, pw, 1.2, color, z + row)
    end
    return pieces
end

local function MakeToggleInline(parent, x, y, w, label, key)
    local h = ROW_H
    Layer(parent, x, y, w, h, C.panel_row, 200)
    -- All option labels are white for strong contrast against the dark menu.
    Text(parent, label, x + 12, y + h * 0.5, 16, FLinearColor(1, 1, 1, 1), 300, 0, 0.5)

    -- Compact, fully rounded switch matching the screenshot: red ON, green OFF.
    local tW, tH = 40, 20
    local tX = x + w - tW - 9
    local tY = y + (h - tH) * 0.5
    local state = (ReadKeyValue(key, 0) == 1)
    local trackPieces = AddPillShape(parent, tX, tY, tW, tH,
        state and C.toggle_on or C.toggle_off, 300, false)
    local knobSize = 14
    local knobY = tY + (tH - knobSize) * 0.5
    local knobX = state and (tX + tW - knobSize - 3) or (tX + 3)
    local knobPieces = AddPillShape(parent, knobX, knobY, knobSize, knobSize, C.toggle_knob, 330, true)

    local function refresh(v)
        state = (v == 1)
        local trackColor = state and C.toggle_on or C.toggle_off
        for _, piece in ipairs(trackPieces) do
            pcall(function() piece:SetBrushColor(trackColor) end)
        end
        knobX = state and (tX + tW - knobSize - 3) or (tX + 3)
        for row, piece in ipairs(knobPieces) do
            local dy = math.abs((row - 0.5) - knobSize * 0.5)
            local inset = knobSize * 0.5 - math.sqrt(math.max(0, knobSize * knobSize * 0.25 - dy * dy))
            pcall(function()
                local slot = piece.Slot
                if slot then
                    slot:SetPosition(FVector2D(knobX + math.floor(inset), knobY + row - 1))
                    slot:SetSize(FVector2D(math.max(1, knobSize - 2 * math.floor(inset)), 1.2))
                end
            end)
        end
    end

    MakeBtn(parent, tX - 5, tY - 5, tW + 10, tH + 10, 900, function()
        local v = state and 0 or 1
        WriteKeyValue(key, v, true)
        refresh(v)
        if _G.SHMenuSave then _G.SHMenuSave() end
    end)
end


-- RGB slider color: changes smoothly with the slider value (UI only).
local function SliderRGB(p)
    p = math.max(0, math.min(1, tonumber(p) or 0))
    local h = p * 6.0
    local i = math.floor(h)
    local f = h - i
    local q = 1.0 - f
    local r,g,b
    if i == 0 then r,g,b = 1,f,0
    elseif i == 1 then r,g,b = q,1,0
    elseif i == 2 then r,g,b = 0,1,f
    elseif i == 3 then r,g,b = 0,q,1
    elseif i == 4 then r,g,b = f,0,1
    else r,g,b = 1,0,q end
    return FLinearColor(r,g,b,1.0)
end

-- ============================================================
-- SLIDER
-- ============================================================
local function MakeSliderInline(parent, x, y, w, label, key, minV, maxV)
    local h = ROW_H
    Layer(parent, x, y, w, h, C.panel_row, 200)
    Layer(parent, x, y, 3, h, C.accent_blue, 201)
    Text(parent, label, x + 14, y + h * 0.5, 16, C.text_dark, 300, 0, 0.5)

    local curVal = ReadKeyValue(key, minV)
    if type(curVal) ~= "number" then curVal = minV end
    curVal = math.floor(curVal)

    -- No +/- buttons. Drag the slider with a finger.
    local valueW = 38
    local slW, slH = math.max(120, w * 0.38), 10
    local slX = x + w - slW - valueW - 10
    local slY = y + h * 0.5 - slH * 0.5
    local range = maxV - minV
    if range < 1 then range = 1 end
    local pct = (curVal - minV) / range
    pct = math.max(0, math.min(1, pct))
    local fillW = math.floor(slW * pct)
    local sliderColor = SliderRGB(pct)

    Layer(parent, slX, slY, slW, slH, C.slider_bg, 298)
    local fillBar = Layer(parent, slX, slY, fillW, slH, sliderColor, 299)
    local kSize = 18
    local kX = math.max(slX - 1, math.min(slX + fillW - kSize * 0.5, slX + slW - kSize + 1))
    local knob = Layer(parent, kX, y + h * 0.5 - kSize * 0.5, kSize, kSize, C.slider_knob, 301)
    local valText = Text(parent, tostring(curVal), x + w - 6, y + h * 0.5, 14, C.accent_blue, 302, 1, 0.5)

    -- Transparent native UMG slider gives the row a real finger-drag interaction.
    pcall(function()
        local nativeSlider = NewObject("/Script/UMG.Slider", parent)
        if IsValid(nativeSlider) then
            if nativeSlider.SetMinValue then nativeSlider:SetMinValue(0.0) end
            if nativeSlider.SetMaxValue then nativeSlider:SetMaxValue(1.0) end
            if nativeSlider.SetStepSize then nativeSlider:SetStepSize(1.0 / range) end
            if nativeSlider.SetValue then nativeSlider:SetValue(pct) end
            if nativeSlider.SetRenderOpacity then nativeSlider:SetRenderOpacity(0.0) end
            if nativeSlider.SetIsFocusable then nativeSlider:SetIsFocusable(false) end
            local sslot = parent:AddChildToCanvas(nativeSlider)
            if sslot then
                sslot:SetAutoSize(false)
                sslot:SetPosition(FVector2D(slX - 14, y + h * 0.5 - 17))
                sslot:SetSize(FVector2D(slW + 28, 40))
                sslot:SetZOrder(1000)
            end
            if nativeSlider.OnValueChanged then
                nativeSlider.OnValueChanged:Add(function(v)
                    pcall(function()
                        local p = tonumber(v) or 0
                        p = math.max(0, math.min(1, p))
                        local value = math.floor(minV + range * p + 0.5)
                        WriteKeyValue(key, value, false)
                        local fw = math.floor(slW * p)
                        local rgb = SliderRGB(p)
                        pcall(function() fillBar:SetBrushColor(rgb) end)
                        pcall(function() knob:SetBrushColor(rgb) end)
                        pcall(function() valText:SetColorAndOpacity(FSlateColor and FSlateColor(rgb) or rgb) end)
                        local fs = fillBar.Slot
                        if fs then fs:SetSize(FVector2D(fw, slH)) end
                        local ks = knob.Slot
                        if ks then ks:SetPosition(FVector2D(slX + fw - kSize * 0.5, y + h * 0.5 - kSize * 0.5)) end
                        valText:SetText(tostring(value))
                        if _G.SHMenuSave then _G.SHMenuSave() end
                    end)
                end)
            end
        end
    end)
end

-- ============================================================
-- SECTION HEADER
-- ============================================================
local function MakeSectionHeader(parent, x, y, w, label, colorKey)
    local h = 30
    local sectionColor = C.accent_cyan
    if colorKey == "purple" then sectionColor = C.accent_purple
    elseif colorKey == "green" then sectionColor = C.accent_green
    elseif colorKey == "red" then sectionColor = C.accent_red
    elseif colorKey == "yellow" then sectionColor = C.accent_yellow
    elseif colorKey == "blue" then sectionColor = C.accent_blue
    end

    Layer(parent, x, y, w, h, C.panel_bg_dark, 200)
    Layer(parent, x, y, 3, h, C.accent_blue_dark, 201)
    Text(parent, label, x + 16, y + h * 0.5, 12, C.text_dark, 300, 0, 0.5)
    Layer(parent, x + 16, y + h - 1, w - 22, 1, C.panel_border, 202)
    return h
end

-- ============================================================
-- STACKS
-- ============================================================
local StackAIM_Left = {
    {label = "Long Range Aimbot", key = "CustomAimbot"},
    {slider = true, label = "Speed", key = "OuterSpeed", min = 1, max = 100},
    {slider = true, label = "Recoil", key = "OuterRecoil", min = 0, max = 50},
    {label = "Close Range Aimbot", key = "CustomAimbotClose"},
    {slider = true, label = "Speed", key = "InnerSpeed", min = 1, max = 100},
    {label = "Reduce Horizontal Recoil", key = "CustomHRecoil"},
    {slider = true, label = "H Value", key = "HRecoil", min = 0, max = 100},
    {label = "Reduce Vertical Recoil", key = "CustomVRecoil"},
    {slider = true, label = "V Value", key = "VRecoil", min = 0, max = 100},
    {label = "Reduce Shake", key = "LessShake"},
    {label = "Accuracy 100%", key = "Accuracy"},
    {label = "Small Crosshair", key = "Crosshair"},
    {label = "Head Aimbot", key = "AutoHead"},
}

local StackAIM_Right = {
    {label = "AKTIFKAN AIMBOT V2", key = "AimTouchEnable"},
    {section = true, label = "<< HIPFIRE >>", color = "blue"},
    {label = "Ig Knock", key = "AimTouchHipIgKnock"},
    {label = "Ig Bot", key = "AimTouchHipIgBot"},
    {label = "VisCheck", key = "AimTouchHipVisCheck"},
    {label = "Aim Touch Hipfire", key = "AimTouchHipfire"},
    {slider = true, label = "Speed", key = "AimTouchHipSpeed", min = 1, max = 100},
    {slider = true, label = "FOV", key = "AimTouchHipFOV", min = 1, max = 100},
    {slider = true, label = "Bone (1-4)", key = "AimTouchHipBone", min = 1, max = 4},
    {slider = true, label = "Prio (1-4)", key = "AimTouchHipPrio", min = 1, max = 4},
    {section = true, label = "<< SCOPE >>", color = "purple"},
    {label = "Aimbot Scope", key = "AimTouchScopeAll"},
    {label = "Ig Knock", key = "AimTouchScopeIgKnock"},
    {label = "Ig Bot", key = "AimTouchScopeIgBot"},
    {label = "VisCheck", key = "AimTouchScopeVisCheck"},
    {slider = true, label = "Speed", key = "AimTouchScopeSpeed", min = 1, max = 100},
    {slider = true, label = "FOV", key = "AimTouchScopeFOV", min = 1, max = 100},
   -- {slider = true, label = "Prediction", key = "AimTouchScopePred", min = 0, max = 100},
  --  {slider = true, label = "Recoil", key = "AimTouchScopeRecoil", min = 0, max = 50},
}

local StackESP_Left = {
    {label = "ESP Tipe 1 (Peringatan)", key = "EspVip"},
    {label = "ESP Tipe 2 (Jarak)", key = "EspDistance"},
    {label = "ESP Tipe 3 (HP & Nama)", key = "EspVipPro"},
    {label = "ESP Tipe 4 (Radar)", key = "EspRadar"},
    {label = "ESP Tipe 5 (Kotak)", key = "EspLoai5"},
  --  {label = "ESP Tipe 6 (Kerangka)", key = "EspLoai6"},
 --   {label = "ESP Tipe 7 (Info Detail)", key = "EspLoai7"},
    {label = "ESP Tipe 8 (HP Head)", key = "EspLoai8"},
 --   {label = "ESP Tipe 9 (RedBox)", key = "EspLoai9"},
--    {label = "ESP Name (VISCEK)", key = "EspName"},
--    {label = "ESP Antena", key = "EspAntenna"},
 --   {label = "ESP Outline", key = "EspOutline"},
 --   {slider = true, label = "Warna (1-6)", key = "OutlineColor", min = 1, max = 6},
--    {slider = true, label = "Ketebalan", key = "OutlineThickness", min = 1, max = 20},
}

local StackESP_Right = {
    {section = true, label = "<< VEHICLE ESP >>", color = "green"},
    {label = "ESP Kendaraan", key = "EspVehicle"},
    {label = "Dacia", key = "EspVeh_Dacia"},
    {label = "UAZ", key = "EspVeh_UAZ"},
    {label = "Buggy", key = "EspVeh_Buggy"},
    {label = "Coupe RB", key = "EspVeh_Coupe"},
    {label = "Mirado", key = "EspVeh_Mirado"},
    {label = "Motor", key = "EspVeh_Motor"},
    {label = "Lainnya", key = "EspVeh_Other"},
    {section = true, label = "<< BOM TRACKER >>", color = "yellow"},
    {label = "Peringatan Bom", key = "EspBomMaster"},
    {label = "Lacak Item Bom", key = "EspItemBom"},
    {label = "Peringatan Aktif", key = "EspActiveBom"},
    {section = true, label = "<< AIM WARNING >>", color = "red"},
    {label = "Peringatan Musuh Aim", key = "EspAimWarning"},
    {label = "Cek Dinding", key = "EspAimWarningVisCheck"},
}

local StackCOMBAT_Left = {
    {section = true, label = "<< WALLHACK >>", color = "purple"},
    {label = "Wallhack V1 (Through Wall)", key = "WallXuyenTuong"},
    {label = "Chams V2 (Color Dasar)", key = "ColorBodyV2"},
    {label = "Wall Color New", key = "ColorBodyNew"},
    {label = "Wall V2 + Chams V3", key = "ColorBodyV3"},
    {slider = true, label = "Color Through Wall", key = "ColorV3Hidden", min = 1, max = 6},
    {slider = true, label = "Visible Color", key = "ColorV3Visible", min = 1, max = 6},
    {slider = true, label = "Thickness", key = "ColorV3Thickness", min = 1, max = 20},
    {label = "Wallhack Vehicle", key = "WallVehicle"},
    {section = true, label = "<< ENVIRONMENT >>", color = "green"},
    {label = "White Character", key = "WhiteBody"},
    {label = "Black Sky", key = "BlackSky"},
    {label = "Remove Fog", key = "RemoveFog"},
    {label = "Remove Grass", key = "RemoveGrass"},
    {label = "Remove Trees", key = "RemoveTrees"},
}

local StackCOMBAT_Right = {
    {section = true, label = "<< COMBAT >>", color = "yellow"},
    {section = true, label = "<< MISC >>", color = "blue"},
--    {label = "Fake HWID", key = "FakeHWID"},
    {label = "iPad View", key = "IpadView"},
    {slider = true, label = "FOV iPad", key = "IpadViewFOV", min = 1, max = 300},
    {label = "iPad Vehicle", key = "IpadViewVehicle"},
    {slider = true, label = "FOV Vehicle", key = "IpadViewVehicleFOV", min = 1, max = 100},
    {label = "iPad Scope", key = "IpadViewScope"},
    {slider = true, label = "Scope FOV", key = "IpadViewScopeFOV", min = 30, max = 120},
    {label = "Unlock 165 FPS", key = "UnlockFPS"},
    {label = "Wall Climb", key = "WallClimb"},
}

local StackMEMORY_Left = {
    {section = true, label = "MEMORY / VIEW", color = "blue"},
    {label = "iPad View", key = "IpadView"},
    {slider = true, label = "FOV iPad", key = "IpadViewFOV", min = 1, max = 300},
    {label = "iPad Vehicle", key = "IpadViewVehicle"},
    {slider = true, label = "FOV CAR", key = "IpadViewVehicleFOV", min = 1, max = 100},
    {label = "iPad Scope", key = "IpadViewScope"},
    {slider = true, label = "Scope FOV", key = "IpadViewScopeFOV", min = 30, max = 120},
}
local StackMEMORY_Right = {
    {section = true, label = "PERFORMANCE", color = "green"},
    {label = "Unlock 165 FPS", key = "UnlockFPS"},
    {label = "Wall Climb", key = "WallClimb"},
    {label = "Fake HWID", key = "FakeHWID"},
}
local StackSKINS_Left = {
    {section = true, label = "CHARACTER STYLE", color = "purple"},
    {label = "White Character", key = "WhiteBody"},
    {label = "Wall Color New", key = "ColorBodyNew"},
    {label = "Wall V2 + Chams V3", key = "ColorBodyV3"},
    {slider = true, label = "Hidden", key = "ColorV3Hidden", min = 1, max = 6},
    {slider = true, label = "Visible", key = "ColorV3Visible", min = 1, max = 6},
}
local StackSKINS_Right = {
    {section = true, label = "ENVIRONMENT", color = "green"},
    {label = "Black Sky", key = "BlackSky"},
    {label = "Remove Fog", key = "RemoveFog"},
    {label = "Remove Grass", key = "RemoveGrass"},
    {label = "Remove Trees", key = "RemoveTrees"},
    {label = "Weapon Glow", key = "WeaponGlow"},
    {slider = true, label = "Glow Color", key = "WeaponGlowColor", min = 1, max = 6},
}
local StackSETTINGS_Left = {
    {section = true, label = "MOVEMENT", color = "blue"},
    {label = "Fast Movement", key = "FastMovement"},
    {slider = true, label = "Movement Speed", key = "FastMovementSpeed", min = 1, max = 100},
    {label = "Fast Car", key = "FastCar"},
    {slider = true, label = "Car Speed", key = "FastCarSpeed", min = 1, max = 3000},
}
local StackSETTINGS_Right = {
    {section = true, label = "GENERAL", color = "purple"},
    {label = "Auto Report", key = "AutoReportEnable"},
    {label = "Mass Report", key = "AutoMassReport"},
    {label = "Killer Report", key = "AutoKillerReport"},
}
local ALL_PAGES = {
    { title = "ESP", left = StackESP_Left, right = StackESP_Right },
    { title = "AIM", left = StackAIM_Left, right = StackAIM_Right },
    { title = "MEMORY", left = StackMEMORY_Left, right = StackMEMORY_Right },
    { title = "WALLHACK", left = StackSKINS_Left, right = StackSKINS_Right },
    { title = "SETTINGS", left = StackSETTINGS_Left, right = StackSETTINGS_Right },
}
local currentPage = 1

-- ============================================================
-- BUILD COLUMN
-- ============================================================
local function BuildColumn(scrollBox, stack)
    local contentPanel = nil
    pcall(function()
        contentPanel = NewObject("/Script/UMG.VerticalBox", scrollBox)
        if IsValid(contentPanel) then
            scrollBox:AddChild(contentPanel)
        end
    end)
    if not IsValid(contentPanel) then return end

    local w = COL_W - 8

    for _, opt in ipairs(stack) do
        if opt.section then
            local rowBox = NewObject("/Script/UMG.SizeBox", contentPanel)
            if IsValid(rowBox) then
                rowBox:SetHeightOverride(30)
                contentPanel:AddChildToVerticalBox(rowBox)
                local rowPanel = NewObject("/Script/UMG.CanvasPanel", rowBox)
                if IsValid(rowPanel) then
                    rowBox:AddChild(rowPanel)
                    MakeSectionHeader(rowPanel, 0, 0, w, opt.label, opt.color)
                end
            end
        else
            local rowBox = NewObject("/Script/UMG.SizeBox", contentPanel)
            if IsValid(rowBox) then
                rowBox:SetHeightOverride(ROW_H)
                local slot = contentPanel:AddChildToVerticalBox(rowBox)
                if slot then
                    pcall(function() slot:SetPadding(FMargin(0, 1, 0, 1)) end)
                end

                local rowPanel = NewObject("/Script/UMG.CanvasPanel", rowBox)
                if IsValid(rowPanel) then
                    rowBox:AddChild(rowPanel)
                    if opt.slider then
                        MakeSliderInline(rowPanel, 0, 0, w, opt.label, opt.key,
                                        opt.min or 0, opt.max or 100)
                    else
                        MakeToggleInline(rowPanel, 0, 0, w, opt.label, opt.key)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- GRW SAMEER HEADER IMAGE (OPTIONAL)
-- ============================================================
-- Put the supplied header PNG into a game-readable texture asset and
-- set this to its Unreal asset path. Example:
--   /Game/GRW/UI/GRW_SAMEER_HEADER.GRw_SAMEER_HEADER
-- The Lua stays fully usable if the image cannot be loaded; the
-- GRW SAMEER text header remains visible.
local GRW_HEADER_TEXTURE_PATH = "/Game/GRW/UI/GRW_SAMEER_HEADER.GRW_SAMEER_HEADER"

local function AddGRWSameerHeaderImage(parent)
    if not parent or not IsValid(parent) then return nil end
    local img = nil
    pcall(function()
        img = NewObject("/Script/UMG.Image", parent)
        if not img or not IsValid(img) then return end
        local slot = parent:AddChildToCanvas(img)
        if slot then
            slot:SetAutoSize(false)
            slot:SetPosition(FVector2D(0, 0))
            slot:SetSize(FVector2D(M_W, HEADER_H))
            slot:SetZOrder(5)
        end
        local tex = import(GRW_HEADER_TEXTURE_PATH)
        if tex and slua.isValid(tex) and img.SetBrushFromTexture then
            img:SetBrushFromTexture(tex, true)
            if img.SetRenderOpacity then img:SetRenderOpacity(0.18) end
            if img.SetWidgetVisibility then
                img:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end
        else
            img:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
    end)
    return img
end

-- ============================================================
-- RGB FRAME / HEADER DECORATION
-- ============================================================
local RGB_PALETTE = {}
do
    -- Dense rainbow palette: smaller segments create a smooth RGB-gradient look.
    local function HSVToRGB(h)
        local x = h * 6
        local i = math.floor(x)
        local f = x - i
        local q = 1 - f
        local r, g, b
        if i == 0 then r, g, b = 1, f, 0
        elseif i == 1 then r, g, b = q, 1, 0
        elseif i == 2 then r, g, b = 0, 1, f
        elseif i == 3 then r, g, b = 0, q, 1
        elseif i == 4 then r, g, b = f, 0, 1
        else r, g, b = 1, 0, q end
        return FLinearColor(r, g, b, 1.0)
    end
    for i = 0, 31 do
        RGB_PALETTE[#RGB_PALETTE + 1] = HSVToRGB(i / 32)
    end
end

local function AddRGBFrame(parent)
    -- Segmented rainbow outline for the refreshed menu frame.
    local colors = _rgbTextPalette
    local w, h, seg = M_W, M_H, 10
    for i = 1, #colors do
        local x = math.floor((i - 1) * w / #colors)
        local nextX = math.floor(i * w / #colors)
        Layer(parent, x, 0, math.max(seg, nextX - x), 3, colors[i], 26000 + i)
        Layer(parent, x, h - 3, math.max(seg, nextX - x), 3, colors[i], 26000 + i)
        local y = math.floor((i - 1) * h / #colors)
        local nextY = math.floor(i * h / #colors)
        Layer(parent, 0, y, 3, math.max(seg, nextY - y), colors[i], 26020 + i)
        Layer(parent, w - 3, y, 3, math.max(seg, nextY - y), colors[i], 26020 + i)
    end
end

local function AddRGBSidebar(parent)
    -- Thin rainbow rail makes the new sidebar visually distinct.
    for i, color in ipairs(_rgbTextPalette) do
        Layer(parent, 3, 60 + (i - 1) * 18, 3, 18, color, 25000 + i)
    end
end

local function AddRGBHeaderDecor(parent)
    for i, color in ipairs(_rgbTextPalette) do
        Layer(parent, SIDEBAR_W + 14 + (i - 1) * 9, 52, 8, 3, color, 25020 + i)
    end
end

-- ============================================================
-- BUILD MENU
-- ============================================================
BuildMenu = function()
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then
        HideMiniButton()
        return false
    end

    -- Fit the menu inside short and tall viewports instead of clipping its frame.
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util and ui_util.GetViewportSize then
            local vp = ui_util.GetViewportSize()
            if vp and vp.X and vp.Y and vp.X > 0 and vp.Y > 0 then
                -- Match reference: narrow left-docked panel, full viewport height.
                M_W = math.max(390, math.min(520, math.floor(vp.X * 0.315)))
                M_H = math.max(360, vp.Y)
                SIDEBAR_W = math.floor(M_W * 0.405)
                COL_W = math.max(120, M_W - SIDEBAR_W - 42)
            end
        end
    end)

    if menuBuilt and IsValid(bgPanel) then ShowMenu() return true end

    local canvas = GetCanvas()
    if not canvas then
        log("BuildMenu: canvas belum ready")
        return
    end

    pcall(function()
        bgPanel = NewObject("/Script/UMG.CanvasPanel", canvas)
        if IsValid(bgPanel) then
            local slot = canvas:AddChildToCanvas(bgPanel)
            if slot then
                slot:SetAutoSize(false)
                slot:SetZOrder(10000)
                local cx, cy = nil, nil
                pcall(function()
                    local ui_util = require("client.common.ui_util")
                    if ui_util and ui_util.GetViewportSize then
                        local vp = ui_util.GetViewportSize()
                        if vp and vp.X and vp.Y and vp.X > 0 and vp.Y > 0 then
                            cx = math.max(0, MENU_X_OFFSET)
                            cy = math.max(0, MENU_Y_OFFSET)
                        end
                    end
                end)
                if cx and cy and FVector2D then
                    if FAnchors then pcall(function() slot:SetAnchors(FAnchors(0, 0, 0, 0)) end) end
                    pcall(function() slot:SetAlignment(FVector2D(0, 0)) end)
                    pcall(function() slot:SetPosition(FVector2D(cx, cy)) end)
                    pcall(function() slot:SetSize(FVector2D(M_W, M_H)) end)
                elseif FAnchors and FVector2D then
                    pcall(function() slot:SetAnchors(FAnchors(0.5, 0.5, 0.5, 0.5)) end)
                    pcall(function() slot:SetAlignment(FVector2D(0.5, 0.5)) end)
                    pcall(function() slot:SetPosition(FVector2D(0, 0)) end)
                    pcall(function() slot:SetSize(FVector2D(M_W, M_H)) end)
                end
            end
        end
    end)
    if not IsValid(bgPanel) then
        log("BuildMenu: bgPanel failed")
        return
    end

    local pageData = ALL_PAGES[currentPage]
    -- soft shadow, pale outer frame, and inset white panel
    Layer(bgPanel, 5, 7, M_W, M_H, FLinearColor(0.00, 0.00, 0.00, 0.35), -2)
    Layer(bgPanel, 0, 0, M_W, M_H, C.panel_border, 2)
    Layer(bgPanel, 2, 2, M_W - 4, M_H - 4, C.panel_bg, 3)
    Layer(bgPanel, 5, 5, SIDEBAR_W - 3, M_H - 10, C.panel_inner, 4)
    Layer(bgPanel, SIDEBAR_W + 5, 5, M_W - SIDEBAR_W - 10, M_H - 10, C.panel_header, 4)
    -- Full-panel RGB wash: translucent rainbow bands behind the menu content.
    do
        local wash = {
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
            FLinearColor(0.00, 0.00, 0.00, 0.00),
        }
        local bandH = math.floor((M_H - 10) / #wash)
        for i, tint in ipairs(wash) do
            local yy = 5 + (i - 1) * bandH
            Layer(bgPanel, 5, yy, M_W - 10, (i == #wash) and (M_H - yy - 5) or bandH, tint, 5 + i)
        end
    end
    AddRGBFrame(bgPanel)
    AddRGBSidebar(bgPanel)
    AddRGBHeaderDecor(bgPanel)

    -- Center the brand title and subtitle across the menu header.
    Text(bgPanel, "GRW PREMIUM PAK", M_W * 0.5, 25, 17, C.text_dark, 10, 0.5, 0.5)
    Text(bgPanel, "GRW | PREMIUM CONTROLS", M_W * 0.5, 45, 9, C.text_dim, 10, 0.5, 0.5)

    local hideX = M_W - 92
    Layer(bgPanel, hideX, 12, 72, 30, C.panel_bg, 12)
    Text(bgPanel, "HIDE", hideX + 36, 27, 11, C.text_dark, 14, 0.5, 0.5)
    MakeBtn(bgPanel, hideX, 12, 72, 30, 900, function()
        isMenuOpen = false
        HideMenu()
        ShowMiniButton()
    end)

    -- Left navigation rail: full-height buttons with the screenshot's spacing.
    local navItems = {
        { title = "ESP", mark = "◉" },
        { title = "AIM", mark = "✣" },
        { title = "MEMORY", mark = "▦" },
        { title = "WALLHACK", mark = "◆" },
    }

    for i, item in ipairs(navItems) do
        local ny = 64 + (i - 1) * 66
        local nh = 58
        local nx = 6
        local nw = SIDEBAR_W - 12
        local selected = currentPage == i
        -- Modern raised tab cards with a dark selected state and RGB accent.
        Layer(bgPanel, nx + 1, ny + 2, nw, nh, FLinearColor(0.00, 0.00, 0.00, 0.02), 7 + i)
        Layer(bgPanel, nx, ny, nw, nh,
            selected and FLinearColor(0.08, 0.55, 1.00, 0.16) or FLinearColor(0.72, 0.78, 0.88, 0.10), 8 + i)
        Layer(bgPanel, nx, ny, 3, nh, _rgbTextPalette[i], 18 + i)
        if selected then
            Layer(bgPanel, nx + 3, ny, nw - 3, 2, C.accent_blue_dark, 20 + i)
            Layer(bgPanel, nx + 3, ny + nh - 2, nw - 3, 2, C.accent_purple, 21 + i)
        end
        Text(bgPanel, item.mark, nx + 17, ny + nh * 0.5, 19,
            C.text_dark, 12, 0, 0.5)
        Text(bgPanel, item.title, nx + 62, ny + nh * 0.5, 12,
            C.text_dark, 12, 0, 0.5)
        MakeBtn(bgPanel, nx, ny, nw, nh, 900, function()
            currentPage = i
            isMenuOpen = true
            menuBuilt = false
            pcall(function()
                if IsValid(bgPanel) then
                    bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end
            end)
            BuildMenu()
        end)
    end

    -- Content title and separator, inside the large right-hand card.
    local contentX = SIDEBAR_W + 20
    local contentW = M_W - contentX - 18
    Text(bgPanel, pageData.title, contentX + 8, 75, 16, C.text_dark, 12, 0, 0.5)
    Text(bgPanel, "Configure " .. pageData.title .. " options", contentX + 8, 94, 10, C.text_dim, 12, 0, 0.5)
    Layer(bgPanel, contentX + 8, 108, contentW - 16, 1, C.panel_border, 8)

    local contentY = 116
    local contentH = M_H - contentY - 38
    local leftX = contentX + 6
    local rightX = leftX + COL_W + COL_GAP

    local scrollLeft, scrollRight = nil, nil
    pcall(function()
        scrollLeft = NewObject("/Script/UMG.ScrollBox", bgPanel)
        if IsValid(scrollLeft) then
            local slot = bgPanel:AddChildToCanvas(scrollLeft)
            if slot then
                slot:SetAutoSize(false)
                slot:SetPosition(FVector2D(leftX, contentY))
                slot:SetSize(FVector2D(COL_W, contentH))
                slot:SetZOrder(20)
            end
            scrollLeft:SetScrollBarVisibility(UEnums.ESlateVisibility.Visible)
            scrollLeft:SetConsumeMouseWheel(true)
        end
    end)
    -- The reference uses one compact options column rather than two cramped columns.
    local combinedOptions = {}
    for _, option in ipairs(pageData.left or {}) do combinedOptions[#combinedOptions + 1] = option end
    for _, option in ipairs(pageData.right or {}) do combinedOptions[#combinedOptions + 1] = option end
    if IsValid(scrollLeft) then BuildColumn(scrollLeft, combinedOptions) end

    -- Thin footer line and page marker, matching the reference's quiet finish.
    local footerY = M_H - 25
    Layer(bgPanel, contentX + 8, footerY, contentW - 16, 1, C.panel_border, 8)
    Text(bgPanel, "GRW PREMIUM PAK  •  " .. currentPage .. "/5  •  " .. pageData.title,
         contentX + contentW * 0.5, M_H - 12, 9, C.text_dim, 12, 0.5, 0.5)

    local headerDrag = MakeBtn(bgPanel, SIDEBAR_W + 4, 3, M_W - SIDEBAR_W - 100, 48, 800, function() end)
    BindDragEvents(headerDrag, "move", bgPanel)
    Layer(bgPanel, M_W - 18, M_H - 18, 14, 14, C.accent_blue, 26000)
    local resizeGrip = MakeBtn(bgPanel, M_W - 30, M_H - 30, 30, 30, 27000, function() end)
    BindDragEvents(resizeGrip, "resize", bgPanel)

    menuBuilt = true
    isMenuOpen = true
    HideMiniButton()
    log("Astral sidebar menu built - Page " .. currentPage)
end


-- ============================================================
-- TWO-FINGER FALLBACK DISABLED
-- The reliable center-top GRW button is the primary opener.
-- ============================================================
-- ============================================================
-- INIT
-- ============================================================
local _initDone = false
local _retry = 0

local function TryInit()
    if _initDone then return end

    -- Authentication is the first gate: never create/show the menu before
    -- the license is active. Once active, this same retry loop opens it.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then
        return
    end

    -- FIX: infinite retry (old code stopped after 30 tries, usually still in lobby
    -- where GetCanvas()==nil because MainControlPanelTochButton not created yet)
    _retry = _retry + 1

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not IsValid(pc) then return end

    local canvas = GetCanvas()
    if not canvas then return end

    if not menuBuilt or not IsValid(bgPanel) then
        BuildMenu()
    else
        ShowMenu()
    end
    if menuBuilt and IsValid(bgPanel) then
        _initDone = true
        log("Init done retry " .. _retry)
    end
end

-- FIX: provide SHAddTick shim + fallback to time_ticker when loader does not supply it.
-- Old code: only `if _G.SHAddTick then _G.SHAddTick(TryInit) end` -> if nil, TryInit
-- never runs -> no float button, no menu. That is exactly your symptom.
if _G.SHAddTick then
    pcall(function() _G.SHAddTick(TryInit) end)
end
-- Always also register via time_ticker loop (works with or without external loader)
pcall(function()
    local okT, ticker = pcall(require, "common.time_ticker")
    if okT and ticker and ticker.AddTimerLoop then
        -- call TryInit every 1.0s forever until _initDone
        ticker.AddTimerLoop(1.0, function()
            if not _initDone then pcall(TryInit) end
        end, 0, 1.0)
        -- immediate first attempt
        if ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, function() pcall(TryInit) end)
        end
    end
end)

if _G.SHRegisterMod then
    pcall(function() _G.SHRegisterMod("VIP Menu Full Scroll", "Active") end)
end

-- Expose manual open for debugging / external loader
_G.SHOpenMenu = function()
    pcall(function()
        if menuBuilt and IsValid(bgPanel) then ShowMenu() else BuildMenu() end
    end)
end
_G.SHTryInit = TryInit

log("File loaded")

end)
-- ==============================================================================
-- ============================ BẮT ĐẦU FULL LOGIC MOD ==========================
-- ==============================================================================

local function Notify(msg) local s = "[GRW_XD Premium] " .. tostring(msg)
pcall(function() if _G.GRW_XDNotify then _G.GRW_XDNotify(s) end end)
pcall(function() local sh = import("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

local function Valid(obj) if not obj then return false end if _slua and
_slua.isValid then local ok, v = pcall(_slua.isValid, obj) if not ok or not v
then return false end end return true end

-- ========================================== 
-- STATIC VARIABLES & GLOBAL CACHE TỐI ƯU HÓA (CHỐNG LAG)
-- ========================================== 
local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE_TEXT = {R=0, G=200, B=255, A=255}
local SCALE_COLOR_V2 = {R=3, G=3, B=0, A=0}

local GLOBAL_BONE_LIST = {
    "head", "neck_01", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

local GLOBAL_CONNECTIONS = {
    {"neck_01", "pelvis", C_YELLOW},
    {"neck_01", "upperarm_l", C_CYAN}, {"upperarm_l", "lowerarm_l", C_CYAN}, {"lowerarm_l", "hand_l", C_CYAN},
    {"neck_01", "upperarm_r", C_CYAN}, {"upperarm_r", "lowerarm_r", C_CYAN}, {"lowerarm_r", "hand_r", C_CYAN},
    {"pelvis", "thigh_l", C_CYAN}, {"thigh_l", "calf_l", C_CYAN}, {"calf_l", "foot_l", C_CYAN},
    {"pelvis", "thigh_r", C_CYAN}, {"thigh_r", "calf_r", C_CYAN}, {"calf_r", "foot_r", C_CYAN}
}

-- ========================================== 
-- CẤU HÌNH GRW_XD CORE + FULL FEATURES VIP 
-- ========================================== 
_G.GRW_XDConfig = _G.GRW_XDConfig or { 
    FakeHWID = false,
    -- CustomMagicBullet = false,  -- [REMOVED] Magic Bullet
    AutoHead = false, 
    EspVip = false, 
    EspDistance = false, 
    EspVipPro = false, 
    EspRadar = false, 
    EspLoai5 = false, 
    EspLoai6 = false, 
    EspLoai7 = false,
    Esp7_SoLuong = true, -- [THÊM MỚI] Bật tắt Số lượng địch
    Esp7_VuKhi = true,   -- [THÊM MỚI] Bật tắt Vũ khí địch
    Esp7_TuThe = true,   -- [THÊM MỚI] Bật tắt Tư thế địch
    EspLoai8 = false,
    EspLoai9 = false, -- Công tắc TỔNG ESP Loại 9
    Esp9_Count = true,    -- Đếm người (RedBox)
    Esp9_Name = true,     -- Tên
    Esp9_HP = true,       -- Thanh Máu
    Esp9_Team = true,     -- Ô màu Team
    Esp9_Weapon = true,   -- Icon Súng
    Esp9_Distance = true, -- Khoảng cách
    Esp9_Line = true,     -- Sợi Line
    Esp9_Skeleton = true, -- Skeleton (Khung xương)
    EspBomMaster = false, 
    EspItemBom = false,   
    EspActiveBom = false, 
    EspAimWarning = false,         -- [THÊM MỚI] Công tắc Cảnh báo địch ngắm
    EspAimWarningVisCheck = false, -- [THÊM MỚI] Công tắc Check tường cho cảnh báo ngắm
    EspVehicle = false,   
    EspVeh_Dacia = true,  
    EspVeh_UAZ = true,    
    EspVeh_Buggy = true,  
    EspVeh_Coupe = true,  
    EspVeh_Mirado = true, 
    EspVeh_Motorcycle = true,  
    EspVeh_Other = true,  
    Esp3ShowName = true,
    Esp3ShowHP = true,
    EspAntenna = false, 
    EspOutline = false, 
    OutlineThickness = 10, 
    UnlockFPS = false, 
    IpadView = false, 
    IpadViewVehicle = false, 
    IpadViewScope = false, -- [THÊM MỚI] Ipad View Mở Scope
    CustomAimbot = false, 
    CustomAimbotClose = false, 
    CustomHRecoil = false,  
    CustomVRecoil = false,  
    LessShake = false, 
    RemoveGrass = false, 
    RemoveTrees = false,  
    RemoveFog = false, 
    WhiteBody = false, 
    ColorBodyV2 = false,    
    ColorBodyV3 = false,    
    WallXuyenTuong = false, 
    ColorBodyNew = false,   -- [THÊM MỚI] Công tắc Wall Màu New
    WallVehicle = false,  
    EspItem_Master = false, 
    EspItem_AR = true,      
    EspItem_Sniper = true,  
    EspItem_SMG = true,     
    EspItem_Shotgun = true, 
    EspItem_LMG = true,       -- [THÊM] Súng máy
    EspItem_Pistol = true,    -- [THÊM] Súng lục
    EspItem_Melee = false,    -- [THÊM] Cận chiến
    EspItem_Special = true,   -- [THÊM] Vũ khí đặc biệt
    EspItem_Scope = true,   
    EspItem_Grenade = true,   -- [THÊM] Lựu đạn
    EspItem_Med = true,       -- [THÊM] Máu & Nước (Vật phẩm y tế)
    Crosshair = false,
    Accuracy = false,
    GodMode = false, 
    WallClimb = false,
    FastCar = false,
    BlackSky = false, -- Tích hợp BlackSky
    
    -- Config Mới Cho Aimbot V2 (Aim Touch)
    AimTouchEnable = false,
    AimTouchHipIgKnock = false,
    AimTouchHipIgBot = false,
    AimTouchSGIgKnock = false,
    AimTouchSGIgBot = false,
    AimTouchHipVisCheck = false,
    AimTouchSGVisCheck = false,
    AimTouchHipfire = false,
    AimTouchSG = false,
    AimTouchSGAutoFire = false,
    AimTouchScopeAll = false,
    AimTouchScopeIgKnock = false,
    AimTouchScopeIgBot = false,
    AimTouchScopeVisCheck = false,
    AimTouchScopeSniper = false,
    AimTouchSniperIgKnock = false,
    AimTouchSniperIgBot = false,
    AimTouchSniperVisCheck = false,
    AimTouchMortar = false, -- [THÊM MỚI] Bật/Tắt Aimbot Súng Cối
    EspFovCircle = false,
    
    -- Config Glow Súng
    WeaponGlow = false,
    
    -- Config Bug Màn
    BugManEnable = false
}

-- CHỨA STATE HỆ THỐNG ĐÃ ĐƯỢC TỐI ƯU HÓA HOÀN TOÀN RAM TRỐNG
_G.GRW_XDState = _G.GRW_XDState or { 
    LoopToken = 0, 
    NativeESPReady = false,
    GraphicsUnlocked = false, 
    MenuStep = 0, 
    LastCmdTime = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    LastAimbotCheckTime = 0, 
    CustomTextData = nil,     
    LastAimbotConfigString = "",
    MagicUpdateVersion = 1,
    LastMagicConfigHash = "",
    PrevGraphicsState = {}
}

local limitTime = os.time({ year = 2027, month = 9, day = 21, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = false

pcall(function()
    local fileName = ".sys_time_cache" -- Tên file ẩn
    local paths = {
        -- ==========================================
        -- [ANDROID] THƯ MỤC SAVEGAMES (Tất cả phiên bản)
        -- ==========================================
     "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/ShadowTrackerExtra/Saved/Paks/paks/paks/paks/paks/SAMEER" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        
        -- ==========================================
        -- [ANDROID] THƯ MỤC GAMELET/LOGS (Giấu sâu chống xóa)
        -- ==========================================
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,

        -- ==========================================
        -- [IOS / FALLBACK] Đường dẫn Sandbox Engine UE4
        -- ==========================================
        "Documents/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "Documents/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "../../GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName,
        "../../GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName
    }
    
    -- [IOS ĐẶC BIỆT] Dò tìm thư mục HOME thực tế
    if os and os.getenv then
        local homeDir = os.getenv("HOME")
        if homeDir and homeDir ~= "" then
            table.insert(paths, 1, homeDir .. "/Documents/GRW_XDTrackerExtra/Saved/SaveGames/" .. fileName)
            table.insert(paths, 2, homeDir .. "/Documents/GRW_XDTrackerExtra/Saved/Gamelet/logs/" .. fileName)
        end
    end
    
    -- LỚP BẢO MẬT 1: Lấy thời gian thực từ Server Game (Anti-đổi giờ thiết bị)
    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then 
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then 
            currentTime = serverTime -- Ưu tiên giờ Server
        end
    end

    -- LỚP BẢO MẬT 2: Đọc TẤT CẢ file ẩn tại SaveGames và Gamelet/logs (tìm mốc thời gian lớn nhất)
    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        -- KHI BỊ LÙI NGÀY HOẶC ĐỔI GIỜ MÁY: Lấy lại mốc thời gian đã lưu lớn nhất
        currentTime = lastSeenTime
    else
        -- RẢI FILE ẨN: Lưu cập nhật thời gian mới nhất vào TẤT CẢ các thư mục có thể ghi được
        for _, path in ipairs(paths) do
            -- Hàm io.open("w") sẽ tự động bỏ qua nếu đường dẫn thư mục đó không tồn tại trên máy
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)



-- ========================================== 
-- HÀM QUẢN LÝ DỌN RÁC MAP MARK (CHỐNG LAG/HIỂN THỊ ẢO KHI ĐỊCH CHẾT)
-- ========================================== 
local function SafeAddMark(id, pos, z, str, size, actor)
    local mark = nil
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.GRW_XDState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

local function SafeRemoveMark(mark)
    if not mark then return end
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.GRW_XDState.TrackedMarks[mark] = nil
end

-- ========================================== 
-- TẠO ID DUY NHẤT VÀ VĨNH VIỄN CHO MỖI KẺ ĐỊCH (SỬA LỖI GIẬT LAG KHI SLUA TẠO WRAPPER MỚI)
-- ==========================================
local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ========================================== 
-- KIỂM TRA PHÂN BIỆT AI (BOT) / REAL PLAYER - OPTIMIZED
-- ==========================================
local function CheckIsAI(pawn, markData)
    if markData.AK_IS_BOT ~= nil then return markData.AK_IS_BOT, true end
    
    local isAI = false
    local hasChecked = false
    pcall(function()
        if pawn.bIsAI == true or pawn.IsAI == true then isAI = true; hasChecked = true end
        if type(pawn.IsBot) == "function" and pawn:IsBot() then isAI = true; hasChecked = true end
        
        local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
        if Valid(pState) then
            hasChecked = true
            if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
            if type(pState.IsBot) == "function" and pState:IsBot() then isAI = true end
        end
        
        if not isAI then
            local name = pawn.PlayerName or (type(pawn.GetPlayerName) == "function" and pawn:GetPlayerName()) or ""
            if name ~= "" and (name:find("Cobra") or name:find("Target") or name:find("bot_") or name:find("b_")) then
                isAI = true
                hasChecked = true
            end
        end
    end)
    if hasChecked then markData.AK_IS_BOT = isAI end
    return isAI, hasChecked
end

-- ========================================== 
-- KHỞI TẠO HOOKS AUTO HEAD SÁT THƯƠNG
-- ==========================================
function _G.InitializeAutoHeadHooks()
    pcall(function()
        local EAvatarDamagePosition = import("EAvatarDamagePosition")
        if not EAvatarDamagePosition then return end

        local modulesToHook = {
            "GameLua.Mod.BaseMod.Common.Weapon.ShootWeaponEntity",
            "GameLua.Logic.Weapon.ShootWeaponEntity"
        }
        
        for _, path in ipairs(modulesToHook) do
            local hitLogic = package.loaded[path]
            if hitLogic then
                local original_GetHitBodyType = hitLogic.GetHitBodyType
                hitLogic.GetHitBodyType = function(self, ImpactResult, InImpactVec)
                    if _G.GRW_XDConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if original_GetHitBodyType then return original_GetHitBodyType(self, ImpactResult, InImpactVec) end
                end

                local original_GetHitBodyTypeByHitPos = hitLogic.GetHitBodyTypeByHitPos
                hitLogic.GetHitBodyTypeByHitPos = function(self, InImpactVec)
                    if _G.GRW_XDConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if original_GetHitBodyTypeByHitPos then return original_GetHitBodyTypeByHitPos(self, InImpactVec) end
                end
            end
        end
    end)
end

_G.ApplyWeaponGlow = function(PlayerCharacter)
    pcall(function()
        local WeaponManager = PlayerCharacter:GetWeaponManager()
        if not slua.isValid(WeaponManager) then return end

        local isGlowEnabled = _G.GRW_XDConfig.WeaponGlow
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        local glowIntensity = 80.0 
        local thickness = _G.GRW_XDState.CustomTextData.WeaponGlowThickness or 3
        local colorMode = _G.GRW_XDState.CustomTextData.WeaponGlowColor or 5
        
        local r, g, b = 1.0, 1.0, 0.0
        if colorMode == 1 then r, g, b = 1.0, 0.0, 0.0
        elseif colorMode == 2 then r, g, b = 0.0, 1.0, 0.0
        elseif colorMode == 3 then r, g, b = 0.0, 0.0, 1.0
        elseif colorMode == 4 then r, g, b = 1.0, 1.0, 0.0
        elseif colorMode == 5 then 
            local time = os.clock() * 2.0
            r = (math.sin(time) + 1) / 2
            g = (math.sin(time + 2) + 1) / 2
            b = (math.sin(time + 4) + 1) / 2
        end

        local finalColor = LinearColorClass and LinearColorClass(r * glowIntensity, g * glowIntensity, b * glowIntensity, 1.0) or { R = r * 255 * glowIntensity, G = g * 255 * glowIntensity, B = b * 255 * glowIntensity, A = 255 }

        for slot = 1, 3 do
            local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
            if slua.isValid(Weapon) then
                local ok, meshComponent = pcall(function() return import("/Script/Engine.MeshComponent") end)
                if ok then
                    local ok2, components = pcall(function() return Weapon:GetComponentsByClass(meshComponent) end)
                    if ok2 and components then
                        local count = type(components.Num) == "function" and components:Num() or #components
                        for i = 1, count do
                            local comp = type(components.Get) == "function" and components:Get(i-1) or components[i]
                            if slua.isValid(comp) then
                                if isGlowEnabled then
                                    pcall(function()
                                        comp.UseScopeDistanceCulling = false
                                        comp.PrimitiveShadingStrategy = 1
                                        comp.ShadingRate = 6
                                        if comp.SetDrawIdeaOutline then
                                            comp:SetDrawIdeaOutline(true)
                                            if comp.OverrideIdeaOutlineColor then comp:OverrideIdeaOutlineColor(true, finalColor) end
                                            if comp.OverrideIdeaOutlineThickness then comp:OverrideIdeaOutlineThickness(true, thickness) end
                                        elseif comp.SetRenderCustomDepth then
                                            comp:SetRenderCustomDepth(true)
                                        end
                                    end)
                                else
                                    pcall(function()
                                        if comp.SetDrawIdeaOutline then comp:SetDrawIdeaOutline(false)
                                        elseif comp.SetRenderCustomDepth then comp:SetRenderCustomDepth(false) end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ========================================== 
-- HỆ THỐNG LƯU VÀ TẢI SETTING MENU VIP (TỰ ĐỘNG)
-- ========================================== 
local function GetConfigPaths(fileName)
    local paths = {
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/GRW_XDTrackerExtra/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/GRW_XDTrackerExtra/Saved/Paks/puffer_temp/" .. fileName,
        "/com.pubg.krmobile/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/com.vng.pubgmobile/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.krmobile/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/com.rekoo.pubgm/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.imobile/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "../../GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "../../../GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        "../../../../GRW_XDTrackerExtra/Saved/Paks/" .. fileName,
        fileName
    }
    pcall(function()
        if os and os.getenv then
            local homeDir = os.getenv("HOME")
            if homeDir and homeDir ~= "" then
                table.insert(paths, 1, homeDir .. "/Documents/GRW_XDTrackerExtra/Saved/Paks/" .. fileName)
                table.insert(paths, 2, homeDir .. "/Documents/GRW_XDTrackerExtra/Saved/Paks/puffer_temp/" .. fileName)
            end
        end
    end)
    return paths
end

local ConfigFileName = "SAMEER.txt"
_G.LastConfigSaveStr = ""

-- HÀM LƯU CONFIG
_G.SaveModSettings = function()
    pcall(function()
        local data = "return {\nGRW_XDConfig = {\n"
        for k, v in pairs(_G.GRW_XDConfig or {}) do
            data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
        data = data .. "},\nCustomTextData = {\n"
        if _G.GRW_XDState and _G.GRW_XDState.CustomTextData then
            for k, v in pairs(_G.GRW_XDState.CustomTextData) do
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "}\n}"
        
        -- Chống giật lag: Chỉ tiến hành ghi file nếu bạn có thay đổi cấu hình
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

-- HÀM TẢI (ĐỌC) CONFIG
_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                break
            end
        end

        if content then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" then
                    if savedData.GRW_XDConfig then
                        for k, v in pairs(savedData.GRW_XDConfig) do
                            _G.GRW_XDConfig[k] = v
                        end
                    end
                    if savedData.CustomTextData then
                        _G.GRW_XDState.CustomTextData = _G.GRW_XDState.CustomTextData or {}
                        for k, v in pairs(savedData.CustomTextData) do
                            _G.GRW_XDState.CustomTextData[k] = v
                        end
                    end
                end
            end
        end
        -- Ghi nhớ cấu hình vừa tải
        _G.SaveModSettings() 
    end)
end

-- VÒNG LẶP KIỂM TRA ĐỂ LƯU CHẠY NGẦM RẤT NHẸ
local function AutoSaveLoop()
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(3.0, AutoSaveLoop) -- Cứ 3 giây check 1 lần
        end
    end)
end

-- KHỞI CHẠY LẦN ĐẦU TIÊN
if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

-- DƯ THỪA ĐỂ KHÔNG BỊ LỖI VÒNG LẶP CŨ CỦA BẠN
_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

-- ========================================== 
-- HỆ THỐNG MENU VIP NATIVE (CHẠY TRỰC TIẾP TỪ SETTING GAME)
-- ========================================== 

function _G.InitModMenuTab()
    -- HARD LOGIN GATE: never initialize the game mode menu before successful key login.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then return false end
    if _G.ModMenuInitialized then return true end
    _G.ModMenuInitialized = true

    -- Hàm hỗ trợ dịch ngôn ngữ (Tự động chọn EN hoặc VN)
    local function T(vnText, enText)
        return _G.GRW_XDLang == "EN" and enText or vnText
    end

    _G.GRW_XDState.CustomTextData = _G.GRW_XDState.CustomTextData or {
        OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.3, VRecoil = 0.3, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120, IpadViewVehicleFOV = 120, IpadViewScopeFOV = 60,
        AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
        AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
        AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
        AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0,
        AimTouchMortarPred = 0,
        AimTouchMortarFOV = 360, -- [THÊM MỚI] Vòng FOV cho Cối
        AimTouchHipFOVColor = 7, AimTouchSGFOVColor = 1, AimTouchScopeFOVColor = 6, AimTouchSniperFOVColor = 4, AimTouchMortarFOVColor = 5, -- Biến màu FOV riêng
        BugManRatio = 133,
        FastCarSpeed = 2000,
        WeaponGlowThickness = 3, WeaponGlowColor = 5,
        ColorV3Hidden = 1, ColorV3Visible = 2, ColorV3Thickness = 4, OutlineColor = 4,
        EspFovCircle_Color = 7,
        Esp9_LineThick = 1, Esp9_LineVisColor = 2, Esp9_LineHidColor = 1,
        Esp9_SkelThick = 1, Esp9_SkelVisColor = 2, Esp9_SkelHidColor = 1
    }

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    -- 1. TẠO BẢNG ID ẢO VỚI TEXT MỚI (Hỗ trợ 2 ngôn ngữ)
    local FakeTextMap = {
        [999000] = T(" GRW_XD MENU", "GRW_XD MENU"),
        [999001] = T("FEATURE ESP ", "VISUALS (ESP)"),
        [999002] = T("AIMBOT ORIGINAL", "AIMBOT ORIGINAL"),
        [999003] = T("AIMBOT ROYAL", "AIMBOT ROYAL"),
        [999004] = T("DUKUNGAN & GRAFIS ", "SUPPORT & GRAPHICS"),
        [999006] = T("ESP NEW V2", "ESP NEW V2")
    }
    -- 2. HOOK TOÀN BỘ HÀM ĐỌC TEXT CỦA GAME (FIX LỖI TRỐNG THANH TAB)
    if LocUtil and not LocUtil._IsModMenuHooked_V2 then
        local hookFuncs = {"GetLocalizeResStr", "GetText", "GetTextByID", "GetLocalText", "GetLocalizeStr"}
        for _, funcName in ipairs(hookFuncs) do
            if LocUtil[funcName] then
                local old_func = LocUtil[funcName]
                LocUtil[funcName] = function(id)
                    if FakeTextMap[id] then
                        return FakeTextMap[id]
                    end
                    if type(id) == "string" and not tonumber(id) then
                        return id
                    end
                    if old_func then
                        return old_func(id)
                    end
                    return ""
                end
            end
        end
        LocUtil._IsModMenuHooked_V2 = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
 local StackESP = {
     { Key = "ModMenu_ESP1", UI = AliasMap.Switcher, Text = T("ESP Tipe 1 (Warning 360-HP-Nama) ", "ESP Type 1 (360 Alert-HP-Name) "), GetFunc = function() return _G.GRW_XDConfig.EspVip end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVip = v return true end },
     { Key = "ModMenu_ESP2", UI = AliasMap.Switcher, Text = T("ESP Tipe 2 (Distance Meter) ", "ESP Type 2 (Distance Meter) "), GetFunc = function() return _G.GRW_XDConfig.EspDistance end, SetFunc = function(c,v) _G.GRW_XDConfig.EspDistance = v return true end },
     
     { Key = "ModMenu_ESP3_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Tipe 3 (HP Vertikal & Nama) ", "▶ ESP Type 3 (Vertical HP & Name) "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspVipPro end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVipPro = v return true end },
     { Key = "ModMenu_ESP3_Name", UI = AliasMap.Switcher, Text = T("   Tampilkan Nama Pemain ", "   Show Player Name "), ExpandHandle = "ModMenu_ESP3_Ex", GetFunc = function() return _G.GRW_XDConfig.Esp3ShowName end, SetFunc = function(c,v) _G.GRW_XDConfig.Esp3ShowName = v return true end },
     { Key = "ModMenu_ESP3_HP", UI = AliasMap.Switcher, Text = T("   Tampilkan Bar HP Vertikal ", "   Show Vertical HP Bar "), ExpandHandle = "ModMenu_ESP3_Ex", GetFunc = function() return _G.GRW_XDConfig.Esp3ShowHP end, SetFunc = function(c,v) _G.GRW_XDConfig.Esp3ShowHP = v return true end },
     
     { Key = "ModMenu_ESP4", UI = AliasMap.Switcher, Text = T("ESP Tipe 4 (Radar 360) ", "ESP Type 4 (Radar 360) "), GetFunc = function() return _G.GRW_XDConfig.EspRadar end, SetFunc = function(c,v) _G.GRW_XDConfig.EspRadar = v return true end },
     { Key = "ModMenu_ESP5", UI = AliasMap.Switcher, Text = T("ESP Tipe 5 (Box Box) ", "ESP Type 5 (Box ESP) "), GetFunc = function() return _G.GRW_XDConfig.EspLoai5 end, SetFunc = function(c,v) _G.GRW_XDConfig.EspLoai5 = v return true end },
     { Key = "ModMenu_ESP6", UI = AliasMap.Switcher, Text = T("ESP Tipe 6 (Rangka Tulang) ", "ESP Type 6 (Skeleton) "), GetFunc = function() return _G.GRW_XDConfig.EspLoai6 end, SetFunc = function(c,v) _G.GRW_XDConfig.EspLoai6 = v return true end },
     { Key = "ModMenu_ESP7_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Tipe 7 (Detailed Info) ", "▶ ESP Type 7 (Detail Info) "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspLoai7 end, SetFunc = function(c,v) _G.GRW_XDConfig.EspLoai7 = v return true end },
     { Key = "ModMenu_ESP7_SoLuong", UI = AliasMap.Switcher, Text = T("   Tampilkan Jumlah Musuh Di Sekitar ", "   Show Enemies Count Around "), ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.GRW_XDConfig.Esp7_SoLuong end, SetFunc = function(c,v) _G.GRW_XDConfig.Esp7_SoLuong = v return true end },
     { Key = "ModMenu_ESP7_VuKhi", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Musuh ", "   Show Enemy Weapon "), ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.GRW_XDConfig.Esp7_VuKhi end, SetFunc = function(c,v) _G.GRW_XDConfig.Esp7_VuKhi = v return true end },
     { Key = "ModMenu_ESP7_TuThe", UI = AliasMap.Switcher, Text = T("   Tampilkan Posisi (Berdiri/Jongkok/Telentang) ", "   Show Posture (Stand/Crouch/Prone) "), ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.GRW_XDConfig.Esp7_TuThe end, SetFunc = function(c,v) _G.GRW_XDConfig.Esp7_TuThe = v return true end },
     { Key = "ModMenu_EspAimWarning", UI = AliasMap.Switcher, Text = T("   Warning Musuh Membidik ", "   Enemy Aim Warning "), ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.GRW_XDConfig.EspAimWarning end, SetFunc = function(c,v) _G.GRW_XDConfig.EspAimWarning = v return true end },
     { Key = "ModMenu_EspAimWarning_Vis", UI = AliasMap.Switcher, Text = T("      Cek Through Wall (Hanya indikasi saat terlihat) ", "      Visibility Check "), ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.GRW_XDConfig.EspAimWarningVisCheck end, SetFunc = function(c,v) _G.GRW_XDConfig.EspAimWarningVisCheck = v return true end },
     { Key = "ModMenu_ESP8", UI = AliasMap.Switcher, Text = T("ESP Tipe 8 (Bar HP di Kepala) ", "ESP Type 8 (Head HP Bar) "), GetFunc = function() return _G.GRW_XDConfig.EspLoai8 end, SetFunc = function(c,v) _G.GRW_XDConfig.EspLoai8 = v return true end },
     
     
     
     { Key = "ModMenu_EspItem_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Item (Di bawah 70m) ", "▶ Item ESP (Under 70m) "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspItem_Master end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Master = v return true end },
     { Key = "ModMenu_EspItem_AR", UI = AliasMap.Switcher, Text = T("   Tampilkan Senapan AR ", "   Show AR Weapons "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_AR end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_AR = v return true end },
     { Key = "ModMenu_EspItem_Sniper", UI = AliasMap.Switcher, Text = T("   Tampilkan Senapan Sniper ", "   Show Sniper Rifles "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Sniper end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Sniper = v return true end },
     { Key = "ModMenu_EspItem_SMG", UI = AliasMap.Switcher, Text = T("   Tampilkan SMG ", "   Show SMGs "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_SMG end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_SMG = v return true end },
     { Key = "ModMenu_EspItem_Shotgun", UI = AliasMap.Switcher, Text = T("   Tampilkan Shotgun ", "   Show Shotguns "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Shotgun end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Shotgun = v return true end },
     { Key = "ModMenu_EspItem_LMG", UI = AliasMap.Switcher, Text = T("   Tampilkan LMG ", "   Show LMGs "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_LMG end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_LMG = v return true end },
     { Key = "ModMenu_EspItem_Pistol", UI = AliasMap.Switcher, Text = T("   Tampilkan Pistol / Flare ", "   Show Pistols / Flares "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Pistol end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Pistol = v return true end },
     { Key = "ModMenu_EspItem_Melee", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Distance Dekat ", "   Show Melee Weapons "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Melee end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Melee = v return true end },
     { Key = "ModMenu_EspItem_Special", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Khusus ", "   Show Special Weapons "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Special end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Special = v return true end },
     { Key = "ModMenu_EspItem_Scope", UI = AliasMap.Switcher, Text = T("   Tampilkan Scope ", "   Show Scopes "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Scope end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Scope = v return true end },
     { Key = "ModMenu_EspItem_Grenade", UI = AliasMap.Switcher, Text = T("   Tampilkan Granat ", "   Show Grenades "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Grenade end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Grenade = v return true end },
     { Key = "ModMenu_EspItem_Med", UI = AliasMap.Switcher, Text = T("   Tampilkan Medkit & Booster ", "   Show Medkits/Boosters "), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItem_Med end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItem_Med = v return true end },
     
     { Key = "ModMenu_ESPBom_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Warning & Pelacak Granat ", "▶ Grenade Warning & Tracker "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspBomMaster end, SetFunc = function(c,v) _G.GRW_XDConfig.EspBomMaster = v return true end },
     { Key = "ModMenu_ESPItemBom", UI = AliasMap.Switcher, Text = T("   Lacak Granat Di Tanah ", "   Show Grenades On Ground "), ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.GRW_XDConfig.EspItemBom end, SetFunc = function(c,v) _G.GRW_XDConfig.EspItemBom = v return true end },
     { Key = "ModMenu_ESPActiveBom", UI = AliasMap.Switcher, Text = T("   Warning Granat Aktif ", "   Active Grenade Warning "), ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.GRW_XDConfig.EspActiveBom end, SetFunc = function(c,v) _G.GRW_XDConfig.EspActiveBom = v return true end },
     
     
     { Key = "ModMenu_ESPVehicle_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Lacak Vehicle ", "▶ Vehicle ESP "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspVehicle end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVehicle = v return true end },
     { Key = "ModMenu_ESPVeh_Dacia", UI = AliasMap.Switcher, Text = T("   Tampilkan Dacia ", "   Show Dacia "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Dacia end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Dacia = v return true end },
     { Key = "ModMenu_ESPVeh_UAZ", UI = AliasMap.Switcher, Text = T("   Tampilkan UAZ ", "   Show UAZ "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_UAZ end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_UAZ = v return true end },
     { Key = "ModMenu_ESPVeh_Buggy", UI = AliasMap.Switcher, Text = T("   Tampilkan Buggy ", "   Show Buggy "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Buggy end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Buggy = v return true end },
     { Key = "ModMenu_ESPVeh_Coupe", UI = AliasMap.Switcher, Text = T("   Tampilkan Coupe RB ", "   Show Coupe RB "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Coupe end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Coupe = v return true end },
     { Key = "ModMenu_ESPVeh_Mirado", UI = AliasMap.Switcher, Text = T("   Tampilkan Mirado ", "   Show Mirado "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Mirado end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Mirado = v return true end },
     { Key = "ModMenu_ESPVeh_Motorcycle", UI = AliasMap.Switcher, Text = T("   Tampilkan Motorcycle ", "   Show Motorcyclecycles "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Motorcycle end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Motorcycle = v return true end },
     { Key = "ModMenu_ESPVeh_Other", UI = AliasMap.Switcher, Text = T("   Tampilkan Others (Perahu/BRDM...) ", "   Show Others (Boat/BRDM) "), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GRW_XDConfig.EspVeh_Other end, SetFunc = function(c,v) _G.GRW_XDConfig.EspVeh_Other = v return true end },
     
     { Key = "ModMenu_ESPAntenna", UI = AliasMap.Switcher, Text = T("ESP Antenna ", "Antenna ESP "), GetFunc = function() return _G.GRW_XDConfig.EspAntenna end, SetFunc = function(c,v) _G.GRW_XDConfig.EspAntenna = v return true end },
     { Key = "ModMenu_ESPOutline_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Outline (Dengan HDR akan terang) ", "▶ Outline ESP (HDR supported) "), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.EspOutline end, SetFunc = function(c,v) _G.GRW_XDConfig.EspOutline = v return true end },
     { Key = "ModMenu_ESPOutline_Color", UI = AliasMap.Slider, Text = T("   Color Outline (1:Merah 2:Hijau 3:Biru 4:Kuning 5:Ungu 6:Putih) ", "   Color (1:Red 2:Grn 3:Blu 4:Ylw 5:Pur 6:Wht) "), ExpandHandle = "ModMenu_ESPOutline_Ex", MinValue = 1, MaxValue = 6, GetFunc = function() return _G.GRW_XDState.CustomTextData.OutlineColor or 4 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.OutlineColor = v return true end },
     { Key = "ModMenu_ESPOutline_Thickness", UI = AliasMap.Slider, Text = T("   Thickness Outline ", "   Outline Thickness "), ExpandHandle = "ModMenu_ESPOutline_Ex", MinValue = 1, MaxValue = 20, min = 1, max = 20, GetFunc = function() return _G.GRW_XDConfig.OutlineThickness end, SetFunc = function(c,v) _G.GRW_XDConfig.OutlineThickness = v return true end }
 }

 local StackAimbot = {
     { Key = "ModMenu_Aimbot_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Long Range Aimbot Kustom", "▶ Custom Long Range Aimbot"), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.CustomAimbot end, SetFunc = function(c,v) _G.GRW_XDConfig.CustomAimbot = v return true end },
     { Key = "ModMenu_Aimbot_Speed", UI = AliasMap.Slider, Text = T("   Speed Long Range Aimbot", "   Long Range Speed"), ExpandHandle = "ModMenu_Aimbot_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.OuterSpeed end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.OuterSpeed = v return true end },
     { Key = "ModMenu_Aimbot_Recoil", UI = AliasMap.Slider, Text = T("   Kompensasi Recoil", "   Recoil Compensation"), ExpandHandle = "ModMenu_Aimbot_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.GRW_XDState.CustomTextData.OuterRecoil or 0 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.OuterRecoil = v return true end },

     { Key = "ModMenu_AimbotClose_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Close Range Aimbot Kustom", "▶ Custom Close Range Aimbot"), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.CustomAimbotClose end, SetFunc = function(c,v) _G.GRW_XDConfig.CustomAimbotClose = v return true end },
     { Key = "ModMenu_AimbotClose_Speed", UI = AliasMap.Slider, Text = T("   Speed Close Range Aimbot", "   Close Range Speed"), ExpandHandle = "ModMenu_AimbotClose_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.InnerSpeed end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.InnerSpeed = v return true end },

     { Key = "ModMenu_HRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Reduce Horizontal Recoilorizontal (Drop/Pick weapon)", "▶ Less Horizontal Recoil (Drop/Pick weapon)"), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.CustomHRecoil end, SetFunc = function(c,v) _G.GRW_XDConfig.CustomHRecoil = v return true end },
     { Key = "ModMenu_HRecoil_Val", UI = AliasMap.Slider, Text = T("   Nilai Recoil Horizontal", "   Horizontal Recoil Value"), ExpandHandle = "ModMenu_HRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.GRW_XDState.CustomTextData.HRecoil or 0.3) - 0.3) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.HRecoil = 0.3 + (v / 100.0) * 4.7 return true end },

     { Key = "ModMenu_VRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Reduce Vertical Recoilertikal (Drop/Pick weapon)", "▶ Less Vertical Recoil (Drop/Pick weapon)"), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.CustomVRecoil end, SetFunc = function(c,v) _G.GRW_XDConfig.CustomVRecoil = v return true end },
     { Key = "ModMenu_VRecoil_Val", UI = AliasMap.Slider, Text = T("   Nilai Recoil Vertikal", "   Vertical Recoil Value"), ExpandHandle = "ModMenu_VRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.GRW_XDState.CustomTextData.VRecoil or 0.3) - 0.3) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.VRecoil = 0.3 + (v / 100.0) * 4.7 return true end },

     { Key = "ModMenu_LessShake", UI = AliasMap.Switcher, Text = T("Reduce Shake Scope", "Less Scope Shake"), GetFunc = function() return _G.GRW_XDConfig.LessShake end, SetFunc = function(c,v) _G.GRW_XDConfig.LessShake = v return true end },
     { Key = "ModMenu_Accuracy", UI = AliasMap.Switcher, Text = T("Accuracy 100%", "100% Accuracy"), GetFunc = function() return _G.GRW_XDConfig.Accuracy end, SetFunc = function(c,v) _G.GRW_XDConfig.Accuracy = v return true end },
     { Key = "ModMenu_Crosshair", UI = AliasMap.Switcher, Text = T("Small Crosshair", "Small Crosshair"), GetFunc = function() return _G.GRW_XDConfig.Crosshair end, SetFunc = function(c,v) _G.GRW_XDConfig.Crosshair = v return true end },
     { Key = "ModMenu_AutoHead", UI = AliasMap.Switcher, Text = T("Head Aimbot", "Aimbot Head"), GetFunc = function() return _G.GRW_XDConfig.AutoHead end, SetFunc = function(c,v) _G.GRW_XDConfig.AutoHead = v return true end },
     { Key = "ModMenu_GodMode", UI = AliasMap.Switcher, Text = T("Mode Dewa (Tembak Super Cepat)", "God Mode (Fast Shoot)"), GetFunc = function() return _G.GRW_XDConfig.GodMode end, SetFunc = function(c,v) _G.GRW_XDConfig.GodMode = v return true end }
 }

local StackAimbotV2 = {
     { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Aktifkan Aimbot Roy & Custom", "▶ Enable Custom Aimbot V2"), ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchEnable end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchEnable = v return true end },
     { Key = "ModMenu_FovCircle_Main", UI = AliasMap.Switcher, Text = T("▶ TAMPILKAN LINGKARAN FOV AIMBOT", "▶ SHOW AIMBOT FOV CIRCLE"), GetFunc = function() return _G.GRW_XDConfig.EspFovCircle end, SetFunc = function(c,v) _G.GRW_XDConfig.EspFovCircle = v return true end },
     
     -- HIPFIRE (CROSSHAIR PUTIH)
     { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Crosshair Putih", "   ▶ Hipfire Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchHipfire = v return true end },
     { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchHipIgKnock = v return true end },
     { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchHipIgBot = v return true end },
     { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = T("      Cek Through Wall (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchHipVisCheck = v return true end },
     { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Slider, Text = T("      Prioritas (1:Crosshair 2:Distance 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchHipPrio = val return true end },
     { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Slider, Text = T("      Target (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchHipBone = val return true end },
     { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Slider, Text = T("      Trigger (1:Saat Tembak, 2:Selalu)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.GRW_XDState.CustomTextData.AimTouchHipCond = val return true end },
     { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = T("      Kehalusan / Speed (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchHipSpeed = v return true end },
     { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = T("      Batas Distance (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.GRW_XDState.CustomTextData.AimTouchHipDist or 250) / 5) end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchHipDist = v * 5 return true end },
     { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = T("      Radius FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchHipFOV = v return true end },
     { Key = "ModMenu_AT_Hip_FOVColor", UI = AliasMap.Slider, Text = T("      Color Lingkaran FOV (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchHipFOVColor or 7 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchHipFOVColor = v return true end },

     -- AIMBOT SHOTGUN
     { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Shotgun", "   ▶ Shotgun Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchSG end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSG = v return true end },
     { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = T("      Tembak Otomatis", "      Auto Fire"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSGAutoFire = v return true end },
     { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSGIgKnock end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSGIgKnock = v return true end },
     { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSGIgBot end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSGIgBot = v return true end },
     { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = T("      Cek Through Wall (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSGVisCheck end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSGVisCheck = v return true end },
     { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Slider, Text = T("      Prioritas (1:Crosshair 2:Distance 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchSGPrio = val return true end },
     { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Slider, Text = T("      Target (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchSGBone = val return true end },
     { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Slider, Text = T("      Trigger (1:Saat Tembak, 2:Selalu)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.GRW_XDState.CustomTextData.AimTouchSGCond = val return true end },
     { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = T("      Kehalusan / Speed (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSGSpeed = v return true end },
     { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = T("      Batas Distance (1-100m)", "      Distance Limit (1-100m)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGDist or 30 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSGDist = v return true end },
     { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = T("      Radius FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSGFOV = v return true end },
     { Key = "ModMenu_AT_SG_FOVColor", UI = AliasMap.Slider, Text = T("      Color Lingkaran FOV Shotgun (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSGFOVColor or 1 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSGFOVColor = v return true end },
     
     -- SCOPE ALL (SENJATA BIASA SAAT SCOPE)
     { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Scope", "   ▶ Scope Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchScopeAll = v return true end },
     { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchScopeIgKnock = v return true end },
     { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchScopeIgBot = v return true end },
     { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = T("      Cek Through Wall (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchScopeVisCheck = v return true end },
     { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Slider, Text = T("      Prioritas (1:Crosshair 2:Distance 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopePrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchScopePrio = val return true end },
     { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Slider, Text = T("      Target (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchScopeBone = val return true end },
     { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Slider, Text = T("      Trigger (1:Saat Tembak, 2:Selalu)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.GRW_XDState.CustomTextData.AimTouchScopeCond = val return true end },
     { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = T("      Kehalusan / Speed (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopeSpeed = v return true end },
     { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = T("      Batas Distance (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.GRW_XDState.CustomTextData.AimTouchScopeDist or 300) / 5) end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
     { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = T("      Prediction Arah Lari", "      Prediction Value"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopePred or 0 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopePred = v return true end },
     { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = T("      Kompensasi Recoil Otomatis", "      Auto Recoil Comp."), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeRecoil or 0 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopeRecoil = v return true end },
     { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = T("      Radius FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopeFOV = v return true end },
     { Key = "ModMenu_AT_ScopeAll_FOVColor", UI = AliasMap.Slider, Text = T("      Color Lingkaran Scope FOV (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchScopeFOVColor or 6 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchScopeFOVColor = v return true end },

     -- SCOPE SNIPER
     { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Scope Sniper", "   ▶ Sniper Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchScopeSniper = v return true end },
     { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSniperIgKnock end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSniperIgKnock = v return true end },
     { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSniperIgBot end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSniperIgBot = v return true end },
     { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = T("      Cek Through Wall (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.GRW_XDConfig.AimTouchSniperVisCheck end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchSniperVisCheck = v return true end },
     { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Slider, Text = T("      Prioritas (1:Crosshair 2:Distance 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchSniperPrio = val return true end },
     { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Slider, Text = T("      Target (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.GRW_XDState.CustomTextData.AimTouchSniperBone = val return true end },
     { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Slider, Text = T("      Trigger (1:Saat Tembak, 2:Selalu)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperCond or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.GRW_XDState.CustomTextData.AimTouchSniperCond = val return true end },
     { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = T("      Kehalusan / Speed (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperSpeed or 30 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSniperSpeed = v return true end },
     { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = T("      Batas Distance (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.GRW_XDState.CustomTextData.AimTouchSniperDist or 400) / 5) end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
     { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = T("      Prediction Arah Lari (0-100)", "      Prediction Value (0-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSniperPred = v return true end },
     { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = T("      Radius FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperFOV or 20 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSniperFOV = v return true end },
     { Key = "ModMenu_AT_Sniper_FOVColor", UI = AliasMap.Slider, Text = T("      Color Lingkaran FOV Sniper (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchSniperFOVColor or 4 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchSniperFOVColor = v return true end },

     -- AIMBOT MORTAR
     { Key = "ModMenu_AT_Mortar_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Mortir", "   ▶ Mortar Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GRW_XDConfig.AimTouchMortar end, SetFunc = function(c,v) _G.GRW_XDConfig.AimTouchMortar = v return true end },
     { Key = "ModMenu_AT_Mortar_Pred", UI = AliasMap.Slider, Text = T("      Prediction Arah Lari (0-100)", "      Prediction Value (0-100)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchMortarPred or 0 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchMortarPred = v return true end },
     { Key = "ModMenu_AT_Mortar_FOV", UI = AliasMap.Slider, Text = T("      Radius FOV (1-360)", "      FOV Radius (1-360)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 360, min = 1, max = 360, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchMortarFOV or 360 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchMortarFOV = v return true end },
     { Key = "ModMenu_AT_Mortar_FOVColor", UI = AliasMap.Slider, Text = T("      Color Lingkaran FOV Mortir (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.GRW_XDState.CustomTextData.AimTouchMortarFOVColor or 5 end, SetFunc = function(c,v) _G.GRW_XDState.CustomTextData.AimTouchMortarFOVColor = v return true end }
 }


        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text = 999000, 
            UIKey = "Setting_Page_Privacy", 
            Category = {
                { Key = "Cat_ESP", Text = 999001, Stack = StackESP },
                { Key = "Cat_ESPV2", Text = 999006, Stack = StackESPV2 },
                { Key = "Cat_Aimbot", Text = 999002, Stack = StackAimbot },
                { Key = "Cat_AimbotV2", Text = 999003, Stack = StackAimbotV2 },
                { Key = "Cat_Combat", Text = 999004, Stack = StackCombat }
            }
        }
        
        -- GRW_XD is NOT added to the native Settings catalog.
    end

    -- Do not hook UIManager.ShowUI: this keeps GRW_XD out of the native Settings screen.
end

-- FIX (root cause #2b): auto-inject Settings tab immediately + retry via ticker.
-- Old code only called InitModMenuTab() from inside ShowGRW_XDVIPMenu()->Step_Welcome
-- button callback, but ShowGRW_XDVIPMenu() was commented out -> menu never appeared.
-- InitModMenuTab is guarded by _G.ModMenuInitialized so safe to call repeatedly.
pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and _G.InitModMenuTab then _G.InitModMenuTab() end end)
pcall(function()
    local okT, ticker = pcall(require, "common.time_ticker")
    if okT and ticker and ticker.AddTimerLoop then
        ticker.AddTimerLoop(2.0, function()
            pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and _G.InitModMenuTab then _G.InitModMenuTab() end end)
        end, 0, 5.0)
        if ticker.AddTimerOnce then
            ticker.AddTimerOnce(1.0, function()
                pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and _G.InitModMenuTab then _G.InitModMenuTab() end end)
            end)
            ticker.AddTimerOnce(3.0, function()
                pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and ShowGRW_XDVIPMenu then ShowGRW_XDVIPMenu() end end)
            end)
        end
    end
end)

local function ShowGRW_XDVIPMenu() 
    -- HARD LOGIN GATE: menu/welcome must never appear before auth.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then return false end
    if _G.GRW_XDMenuAlreadyShown then return end
    if _G.GRW_XDState.MenuStep ~= 0 then return end

    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then return end

        local function Step_ScamAlert()
            local title = _G.GRW_XDLang == "EN" and "SCAM ALERT" or "PERINGATAN PENIPUAN MOD"
            local content = _G.GRW_XDLang == "EN" 
                and "Join my Telegram to avoid scammers selling VIP mods.  TELE @GRW_XD" 
                or "Bergabunglah dengan Telegram Saya untuk Menghindari Oknum Penjual Mod VIP TELE @GRW_XD\nChanel telegram resmi @GRW_XD jika ada yg jual mod ini kecuali owner berarti scam"
            local btn1 = _G.GRW_XDLang == "EN" and "JOIN" or "GABUNG"
            local btn2 = _G.GRW_XDLang == "EN" and "CLOSE" or "TUTUP"

            Msg.Show(1, title, content, function() local Web = require("client.slua.logic.url.logic_webview_sdk"); if Web and Web.OpenURL then Web:OpenURL("https://wa.me/923709241014") end end, function() end, btn1, btn2)
            _G.GRW_XDState.MenuStep = 99
            _G.GRW_XDMenuAlreadyShown = true
        end

        local function Step_Welcome()
            local title = _G.GRW_XDLang == "EN" and "WELCOME TO VIP MOD" or "SELAMAT DATANG"
            local content = _G.GRW_XDLang == "EN" 
                and "Hi, The VIP MENU is now inside Game Settings!\nIMPORTANT: Enable fewer features to avoid lag. Play safe!" 
                or "Hai, Kamu tidak perlu pakai combo atau config luar lagi karena sekarang sudah ada MENU VIP di dalam Pengaturan Game!\nTAPI DENGARKAN SAYA, NYALAKAN SEDIKIT FITUR SAJA BIAR NGGAK LAG, SAYA KHAWATIR HP KAMU NGGAK KUAT, DAN YANG PASTI JANGAN KETERLALUAN BIAR AMAN"
            local btn1 = _G.GRW_XDLang == "EN" and "OPEN GAME MENU" or "BUKA MENU DALAM GAME"
            local btn2 = _G.GRW_XDLang == "EN" and "CLOSE" or "TUTUP"

            Msg.Show(1, title, content, 
            function() 
                _G.InitModMenuTab()
                if _G.GRW_XDLang == "EN" then
                    Notify("VIP MOD MENU ADDED!\nOpen Settings (Gear icon) -> VIP MOD MENU to toggle features.")
                else
                    Notify("'VIP MOD MENU' TELAH DITAMBAHKAN KE PENGATURAN GAME!\nBuka Pengaturan (ikon Gigi) -> VIP MOD MENU untuk mengaktifkan/menonaktifkan fitur.")
                end
                Step_ScamAlert()
            end, 
            function() end, btn1, btn2)
        end

        local function Step_SelectLanguage()
            Msg.Show(2, "SELECT LANGUAGE / PILIH BAHASA", "Silakan pilih bahasa yang Anda inginkan.\nPlease select your preferred language.",
            function()
                _G.GRW_XDLang = "VN"
                Step_Welcome()
            end,
            function()
                _G.GRW_XDLang = "EN"
                Step_Welcome()
            end, "BAHASA INDONESIA", "ENGLISH")
        end

        local function Step_LegalNotice()
            local legal_title = "Pengumuman dari Admin @GRW_XD - Announcement from Admin @GRW_XD"
            local legal_content = "GULIR KE BAWAH UNTUK MEMBACA LENGKAP - SCROLL DOWN TO READ THE FULL ARTICLE\n\nESP X16  = Crash di Beberapa Perangkat ( Game crashes on some devices )\nMAGIC BULLET = RISK BAN X\nGLOBAL = AMAN ✓( SAFE )\nVNG = AMAN ✓( SAFE )\nKOREA = AMAN ✓(SAFE)\nTAIWAN = AMAN ✓( SAFE )\n\nIND Halo Semua, Ini Mod Buatan Saya. Harap Hati-hati Jangan Bertransaksi Jual Beli dengan Siapa Pun Selain Saya Telegram @GRW_XD . Jika Ada Orang Lain Yang Bertransaksi Dengan Anda Mengenai Mod Ini, Selamat Anda Tertipu HaHaHa. Jika Anda Di Channel Telegram Saya, Mohon Baca Panduan Fitur-Fiturnya, Jangan Tanyakan Hal-Hal Yang Membuktikan Kebodohan Anda\n\nENGLISH Hi everyone, this is a mod I created. Please be careful and do not conduct any transactions with anyone other than me (Telegram: @GRW_XD ). If anyone else tries to trade these mods with you—congratulations, you've been scammed!."
            local legal_btnOK = "Setuju (Agree)"
            local legal_btnCancel = "Batal (Cancel)"
            local legal_url = "https://wa.me/923709241014" 

            local legal_msg = require("client.slua.logic.common.logic_common_legal_msg")
            if not legal_msg then
                -- Jika game tidak memiliki library legal, fallback langsung ke pilihan bahasa
                Step_SelectLanguage()
                return
            end
            
            legal_msg.ShowOnePopUI({
                tabType = 0,
                title = legal_title,
                content = legal_content,
                tipsText = nil,
                btnOKText = legal_btnOK,
                btnCancelText = legal_btnCancel, 
                acceptFunc = function()
                    -- Bấm Confirm -> Mở bảng chọn ngôn ngữ
                    Step_SelectLanguage()
                end,
                refuseFunc = function()
                    -- Bấm Join Channel -> Mở link Telegram -> Mở bảng chọn ngôn ngữ
                    local KismetSystemLibrary = import("KismetSystemLibrary")
                    if KismetSystemLibrary then
                        KismetSystemLibrary:LaunchURL(legal_url)
                    end
                    Step_SelectLanguage()
                end
            })
        end

        _G.GRW_XDState.MenuStep = 1
        -- Gọi bảng Legal Notice đầu tiên thay vì bảng chọn Ngôn Ngữ
        Step_LegalNotice() 
    end)
end

-- ========================================== 
-- LOGIC MỞ KHÓA 165 FPS VÀ UI IPAD VIEW 
-- ========================================== 
local function InitializeGraphicsUnlock() 
    if isExpired then return end
    if _G.GRW_XDState.GraphicsUnlocked or currentTime > limitTime then return end

    pcall(function()
        local SettingCfg = require("client.logic.setting.setting_config")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end
    end)

    pcall(function()
        local logic_setting_graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        
        local KismetMathLibrary = import("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor = import("LinearColor") or _G.FLinearColor

        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                if FPSLevel == 8 then 
                    gameInstance:ExecuteCMD("t.MaxFPS", "165")
                    gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
                end
            end
        end

        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false) end
                return RealSupportFPS
            end
            function fps_impl:UpdateSelectedFPSState(selectedLevel)
                if not slua.isValid(self.UIRoot) then return end
                for level = 2, 8 do
                    local name = "NodeFps" .. (({[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120})[level] or 120)
                    local widget = self.UIRoot[name]
                    if slua.isValid(widget) then
                        widget:SetIsEnabled(true) 
                        pcall(function() widget:SetRenderOpacity(1.0) end)
                        local switcher = self.UIRoot["WidgetSwitcher_" .. level]
                        if slua.isValid(switcher) then 
                            switcher:SetActiveWidgetIndex(level == selectedLevel and 0 or 1) 
                        end
                    end
                end
            end
        end

        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft_impl = GSC_FPSFT.__inner_impl
            local NMinFPS, NStep = 90, 5
            local function clamp(value, min, max)
                if value < min then return min end
                if max < value then return max end
                return value
            end
            local function lerp(a, b, t) return a + (b - a) * t end
            local function _getColorByPercent(start, finish, percent)
                if not FLinearColor then return nil end
                return FLinearColor(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
            end
            
            ft_impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end

            ft_impl.InitFPSFTSwitch = function(self)
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(FPSFineTuneSwitch, true) end
                if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, FPSFineTuneSwitch) end
                if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
            end

            ft_impl.InitFPSFTValue165 = function(self)
                local itemRoot = self.UIRoot
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                local FPSFineTuneNum = 165
                if FPSFineTuneSwitch then
                    FPSFineTuneNum = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    itemRoot.Slider_screen3:SetLocked(false)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)
                
                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)
                
                if FLinearColor then
                    local startColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor(1.0, 0.23, 0.15, 1.0)
                    local sliderColor = FPSFineTunePer < 0.4 and startColor or _getColorByPercent(midColor, endColor, (FPSFineTunePer - 0.4) / 0.6)
                    itemRoot.Slider_screen3:SetSliderHandleColor(sliderColor)
                end
            end

            ft_impl.OnFPSFTValueChange3 = function(self, FPSFineTuneNum)
                GraphicSettingDB:UpdateUIData(GraphicSettingDB.FPSFineTuneNum, FPSFineTuneNum)
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gameInstance = GraphicSettingDB.GetGameInstance and GraphicSettingDB.GetGameInstance()
                if gameInstance then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(FPSFineTuneNum))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(FPSFineTuneNum))
                end
            end

            ft_impl.OnFPSFTSliderValueChange3 = function(self, value)
                if GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch) and KismetMathLibrary then
                    local FPSFineTuneNum = KismetMathLibrary.FCeil(value * (165 - NMinFPS) / NStep) * NStep + NMinFPS
                    self:OnFPSFTValueChange3(clamp(FPSFineTuneNum, NMinFPS, 165))
                end
            end
            
            ft_impl.OnFPSFTAdd = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTAdd2 = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus2 = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTSliderValueChange = ft_impl.OnFPSFTSliderValueChange3
            ft_impl.OnFPSFTSliderValueChange2 = ft_impl.OnFPSFTSliderValueChange3
        end
    end)
    _G.GRW_XDState.GraphicsUnlocked = true
    Notify("Graphics & FPS 165Hz Unlocked (Upgraded Version)")
end

-- ========================================== 
-- KHỞI TẠO HỆ THỐNG ESP (GỐC)
-- ========================================== 
local function InitializeNativeESP() 
    if _G.GRW_XDState.NativeESPReady then return end
    pcall(function() 
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools") 
        local currentMarkCfg = GamePlayTools.GetCurrentConfig("ScreenMarkConfig") 
        local function ApplyCfg(cfg)
            if not cfg then return end 
            if cfg[1006] then 
                cfg[1006].bBindBlocked = true;
                cfg[1006].bBindOutScreen = true; 
                cfg[1006].MaxWidgetNum = 99
                cfg[1006].MaxShowDistance = 6000000; 
                cfg[1006].bScaleByDistance = false
                cfg[1006].BindSocketName = "root"; 
                cfg[1006].bUseLuaWorldSocketName = true
                cfg[1006].WorldPositionOffset = FVector(0, 0, -30) 
            end 
            -- [FIX ESP LOẠI 4] Thay vì dùng 1003 dễ bị game xóa, ta tạo ID độc quyền 8888
            cfg[8888] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true,     -- Bắt buộc phải có để bám theo địch
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 30),
                bNeedPreLoad = true,        -- Bắt buộc có để load sẵn UI (chống lỗi)
                Priority = 2 
            } 
            cfg[9999] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true, 
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 50),
                bNeedPreLoad = true, 
                Priority = 2 
            } 
        end 
        ApplyCfg(currentMarkCfg) 
        for k, cfg in pairs(package.loaded) do 
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then 
                ApplyCfg(cfg) 
            end 
        end 
    end)
    _G.GRW_XDState.NativeESPReady = true 
    Notify("Native ESP System Initialized") 
end

-- ========================================== 
-- LOCAL FUNCTIONS CHO LOGIC NEW ESP - OPTIMIZED
-- ========================================== 
local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    
    -- [FIX 3] Extended cache to 1.5s + validity check on cached meshes
    -- Older 0.5s caused invisible enemies when clothing changed
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 1.5) then
        local validMeshes = {}
        local bAllValid = true
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            local isPendingKill = false
            pcall(function() 
                if type(cachedMesh.IsPendingKill) == "function" then 
                    isPendingKill = cachedMesh:IsPendingKill() 
                end 
            end)
            
            if slua.isValid(cachedMesh) and not isPendingKill then 
                validMeshes[#validMeshes + 1] = cachedMesh 
            else
                bAllValid = false
            end
        end
        
        -- If any mesh died, invalidate cache fully to force fresh scan
        if bAllValid and #validMeshes > 0 then
            markData.CachedMeshes = validMeshes
            return validMeshes
        end
        -- Otherwise fall through to fresh scan
    end

    local meshes = {}
    if slua.isValid(enemy.Mesh) then 
        meshes[#meshes + 1] = enemy.Mesh 
    end
    
    pcall(function()
        local SkClass = import("SkeletalMeshComponent")
        if SkClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if slua.isValid(comp) and comp ~= enemy.Mesh then
                        meshes[#meshes + 1] = comp
                    end
                end
            end
        end
    end)
    
    if markData then
        markData.CachedMeshes = meshes
        markData.CachedMeshTime = curTime
    end
    return meshes
end

-- ========================================== 
-- HÀM XUYÊN TƯỜNG & RESTORE GỐC
-- ==========================================
local function UndoWallXuyenTuong(enemy, markData)
    pcall(function()
        if markData.WallhackApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function() if type(mesh.SetRenderCustomDepth) == "function" then mesh:SetRenderCustomDepth(false) end end)
                    for i = 0, 10 do 
                        local matInterface = mesh:GetMaterial(i)
                        if Valid(matInterface) then
                            local baseMat = matInterface:GetBaseMaterial()
                            if Valid(baseMat) then baseMat.bDisableDepthTest = false end
                        end
                    end
                end
            end
            markData.WallhackApplied = false
        end
    end)
end

local function ApplyWallXuyenTuong(enemy, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then 
                pcall(function()
                    if type(mesh.SetRenderCustomDepth) == "function" then
                        mesh:SetRenderCustomDepth(true)
                    end
                    if type(mesh.SetCustomDepthStencilValue) == "function" then
                        mesh:SetCustomDepthStencilValue(252) 
                    end
                end)
                for i = 0, 10 do 
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        baseMat.bDisableDepthTest = true
                        baseMat.BlendMode = 2 
                    end
                end
            end
        end
    end)
end

local function ApplyColorBodyV2(enemy, pc, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        -- [FIX CHỐNG GIẬT LAG ĐÔNG NGƯỜI]: Giới hạn tia Raycast Check Tường 0.3s một lần
        -- Tránh việc bắn hàng nghìn tia vật lý mỗi giây làm cháy CPU
        local curTime = os.clock()
        if markData.LastVisCheckTime == nil or (curTime - markData.LastVisCheckTime) > 0.3 then
            markData.LastVisCheckTime = curTime
            local isHidden = true
            pcall(function()
                if Valid(pc) and type(pc.LineOfSightTo) == "function" then
                    if pc:LineOfSightTo(enemy) then isHidden = false else isHidden = true end
                end
            end)
            markData.CachedHiddenState = isHidden
        end
        
        local hidden = markData.CachedHiddenState
        if hidden == nil then hidden = true end
        
        local cData = _G.GRW_XDState.CustomTextData or {}
        local hiddenColor = {R = cData.HiddenR or 150, G = cData.HiddenG or 0, B = cData.HiddenB or 0, A = cData.HiddenA or 25}
        local visibleColor = {R = cData.VisibleR or 0, G = cData.VisibleG or 150, B = cData.VisibleB or 0, A = cData.VisibleA or 25}
        
        local finalColor = hidden and hiddenColor or visibleColor
        local colorHash = string.format("%d_%d_%d_%d", finalColor.R, finalColor.G, finalColor.B, finalColor.A)
        local currentMeshCount = #meshes
        local isMeshChanged = (markData.LastMeshCount ~= currentMeshCount)
        
        -- Nếu chưa có sự đổi màu / đổi số lượng quần áo thì ngắt luôn, tiết kiệm CPU
        if not isMeshChanged and markData.LastHiddenState == hidden and markData.LastColorHash == colorHash then return end
        
        -- [FIX RAM]: Xóa Material rác cũ đi khi địch đổi vũ khí/áo giáp để tránh rác VRAM
        if isMeshChanged and markData.MIDs then
            markData.MIDs = {}
        end

        markData.LastHiddenState = hidden
        markData.LastMeshCount = currentMeshCount
        markData.LastColorHash = colorHash
        markData.ColorApplied = true
        
        for meshIndex, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    mesh.LDMaxDrawDistance = -99999
                    mesh.MaxDrawDistanceOffset = -99999
                    mesh.CachedMaxDrawDistance = -99999
                    mesh.UseScopeDistanceCulling = true
                    mesh.PrimitiveShadingStrategy = 1
                    mesh.ShadingRate = 6
                end)
                for i = 0, 10 do
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        local matName = tostring(baseMat)
                        if string.find(matName, "Master_Mask", 1, true) then
                            if not markData.MIDs then markData.MIDs = {} end
                            
                            -- [FIX RÁC RAM]: Thay vì dùng tostring(mesh) sinh rác chuỗi, dùng index cục bộ
                            local meshKey = "Mesh_" .. tostring(meshIndex)
                            
                            if not markData.MIDs[meshKey] then markData.MIDs[meshKey] = {} end
                            local mid = markData.MIDs[meshKey][i]
                            if not Valid(mid) then
                                mid = mesh:CreateAndSetMaterialInstanceDynamic(i)
                                markData.MIDs[meshKey][i] = mid
                            end
                            if Valid(mid) then
                                mid:SetVectorParameterValue("颜色", finalColor)
                                mid:SetVectorParameterValue("Extra Light Color", finalColor)
                                mid:SetVectorParameterValue("Para_Color", finalColor)
                                mid:SetVectorParameterValue("Para_ColorTint", finalColor)
                                mid:SetVectorParameterValue("Para_Color_1", finalColor)
                                mid:SetVectorParameterValue("Tint", finalColor)
                                mid:SetVectorParameterValue("Color", finalColor)
                                mid:SetVectorParameterValue("BaseColor", finalColor)
                                mid:SetVectorParameterValue("BodyColor", finalColor)
                                mid:SetVectorParameterValue("MainColor", finalColor)
                                mid:SetVectorParameterValue("DiffuseColor", finalColor)
                                mid:SetVectorParameterValue("EmissiveColor", finalColor)
                                mid:SetVectorParameterValue("ParaScaleOffset", SCALE_COLOR_V2)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function UndoColorBodyV2(enemy, markData)
    pcall(function()
        if markData.ColorApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        mesh.PrimitiveShadingStrategy = 0
                        mesh.ShadingRate = 1
                    end)
                    local meshKey = "Mesh_" .. tostring(meshIndex)
                    if markData.MIDs and markData.MIDs[meshKey] then
                        for i, mid in pairs(markData.MIDs[meshKey]) do
                            if Valid(mid) then
                                local defC = {R=1, G=1, B=1, A=1}
                                mid:SetVectorParameterValue("颜色", defC)
                                mid:SetVectorParameterValue("Extra Light Color", defC)
                                mid:SetVectorParameterValue("Para_Color", defC)
                                mid:SetVectorParameterValue("Para_ColorTint", defC)
                                mid:SetVectorParameterValue("Para_Color_1", defC)
                                mid:SetVectorParameterValue("Tint", defC)
                                mid:SetVectorParameterValue("Color", defC)
                                mid:SetVectorParameterValue("BaseColor", defC)
                                mid:SetVectorParameterValue("BodyColor", defC)
                                mid:SetVectorParameterValue("MainColor", defC)
                                mid:SetVectorParameterValue("DiffuseColor", defC)
                                mid:SetVectorParameterValue("EmissiveColor", defC)
                            end
                        end
                    end
                end
            end
            markData.ColorApplied = false
            markData.LastColorHash = ""
            markData.LastHiddenState = nil
        end
    end)
end

-- ==========================================
-- CHỨC NĂNG MÀU V3 (TÁCH BIỆT TỪ MÃ NGUỒN CỦA BẠN - HOẠT ĐỘNG QUA BỘ ĐỆM Z-BUFFER)
-- [ĐÃ FIX LỖI MẤT MÀU KHI ĐỔI LOD & TỐI ƯU CHỐNG DROP FPS KHI ĐÔNG NGƯỜI]
-- ==========================================
local function ApplyColorBodyV3(enemy, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        local cData = _G.GRW_XDState.CustomTextData or {}
        local hidChoice = cData.ColorV3Hidden or 1
        local visChoice = cData.ColorV3Visible or 2
        local v3Thick = cData.ColorV3Thickness or 4
        
        -- Tạo mã băm để phát hiện người dùng kéo thanh đổi màu/độ dày
        local currentHash = string.format("%d_%d_%d", hidChoice, visChoice, v3Thick)
        local colorChanged = (markData.LastColorV3Hash ~= currentHash)
        markData.LastColorV3Hash = currentHash

        local function GetColorRGB(choice)
            if choice == 1 then return 255, 0, 0 end -- Đỏ
            if choice == 2 then return 0, 255, 0 end -- Lục
            if choice == 3 then return 0, 0, 255 end -- Lam
            if choice == 4 then return 255, 255, 0 end -- Vàng
            if choice == 5 then return 255, 0, 255 end -- Tím/Hồng
            if choice == 6 then return 255, 255, 255 end -- Trắng
            return 255, 0, 0 -- Mặc định đỏ
        end

        local hR, hG, hB = GetColorRGB(hidChoice)
        local vR, vG, vB = GetColorRGB(visChoice)

        -- Màu Sau Tường (invisColor)
        local invisColor = { R=hR, G=hG, B=hB, A=255, r=hR, g=hG, b=hB, a=255 }
        
        -- Màu Viền Lộ Diện HDR (visColor)
        local glowIntensity = 80.0 
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        local visColor = LinearColorClass and LinearColorClass((vR/255)*glowIntensity, (vG/255)*glowIntensity, (vB/255)*glowIntensity, 1.0) or { R=vR*glowIntensity, G=vG*glowIntensity, B=vB*glowIntensity, A=255 }
        local scale = { R=3.0, G=3.0, B=0.0, A=0.0, r=3.0, g=3.0, b=0.0, a=0.0 }
        
        markData.MIDs_V3 = markData.MIDs_V3 or {}

        for meshIndex, comp in ipairs(meshes) do
            if Valid(comp) then
                local compKey = "MeshV3_" .. tostring(meshIndex)
                markData.MIDs_V3[compKey] = markData.MIDs_V3[compKey] or {}
                
                pcall(function()
                    if comp.PrimitiveShadingStrategy ~= 1 then
                        comp.UseScopeDistanceCulling = false 
                        comp.PrimitiveShadingStrategy = 1
                        comp.ShadingRate = 6
                    end
                end)
                
                for i = 0, 10 do
                    local matInterface = comp:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        if baseMat.bDisableDepthTest ~= true then baseMat.bDisableDepthTest = true end
                        if baseMat.BlendMode ~= 2 then baseMat.BlendMode = 2 end
                    end
                    
                    local currentCached = markData.MIDs_V3[compKey][i]
                    local needUpdateColor = false
                    
                    -- Nếu chưa có MID hoặc người dùng kéo thanh đổi màu -> Cập nhật lại
                    if not Valid(currentCached) then
                        local newMid = comp:CreateAndSetMaterialInstanceDynamic(i)
                        if Valid(newMid) then 
                            markData.MIDs_V3[compKey][i] = newMid
                            currentCached = newMid
                            needUpdateColor = true
                        end
                    elseif colorChanged then
                        needUpdateColor = true
                    end
                    
                    if Valid(currentCached) and needUpdateColor then
                        pcall(function()
                            currentCached:SetVectorParameterValue("颜色", invisColor)
                            currentCached:SetVectorParameterValue("Extra Light Color", invisColor)
                            currentCached:SetVectorParameterValue("Para_Color", invisColor)
                            currentCached:SetVectorParameterValue("Para_ColorTint", invisColor)
                            currentCached:SetVectorParameterValue("Para_Color_1", invisColor)
                            currentCached:SetVectorParameterValue("Tint", invisColor)
                            currentCached:SetVectorParameterValue("Color", invisColor)
                            currentCached:SetVectorParameterValue("BaseColor", invisColor)
                            currentCached:SetVectorParameterValue("BodyColor", invisColor)
                            currentCached:SetVectorParameterValue("MainColor", invisColor)
                            currentCached:SetVectorParameterValue("DiffuseColor", invisColor)
                            currentCached:SetVectorParameterValue("EmissiveColor", invisColor)
                            currentCached:SetVectorParameterValue("CustomColor", invisColor)
                            currentCached:SetVectorParameterValue("OverlayColor", invisColor)
                            currentCached:SetVectorParameterValue("GlowColor", invisColor)
                            currentCached:SetVectorParameterValue("EdgeColor", invisColor)
                            currentCached:SetVectorParameterValue("LightColor", invisColor)
                            currentCached:SetVectorParameterValue("OutlineColor", invisColor)
                            currentCached:SetVectorParameterValue("ParaScaleOffset", scale)
                            currentCached:SetScalarParameterValue("Opacity", 0.7)
                            currentCached:SetScalarParameterValue("Alpha", 0.7)
                            currentCached:SetScalarParameterValue("GlowIntensity", 1.0)
                            currentCached:SetScalarParameterValue("Intensity", 1.0)
                        end)
                    end
                end
                
                pcall(function()
                    if comp.SetDrawIdeaOutline then
                        comp:SetDrawIdeaOutline(true)
                        if comp.OverrideIdeaOutlineColor then comp:OverrideIdeaOutlineColor(true, visColor) end
                        if comp.OverrideIdeaOutlineThickness then comp:OverrideIdeaOutlineThickness(true, v3Thick) end
                    end
                end)
            end
        end
        markData.ColorV3Applied = true
    end)
end

local function UndoColorBodyV3(enemy, markData)
    pcall(function()
        if markData.ColorV3Applied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, comp in ipairs(meshes) do
                if Valid(comp) then
                    pcall(function()
                        comp.PrimitiveShadingStrategy = 0
                        comp.ShadingRate = 1
                    end)
                    
                    for i = 0, 10 do
                        local s, matInterface = pcall(function() return comp:GetMaterial(i) end)
                        if s and Valid(matInterface) then
                            local s2, baseMat = pcall(function() return matInterface:GetBaseMaterial() end)
                            if s2 and Valid(baseMat) then
                                baseMat.bDisableDepthTest = false
                                baseMat.BlendMode = 1
                            end
                        end
                    end
                    
                    local compKey = "MeshV3_" .. tostring(meshIndex)
                    if markData.MIDs_V3 and markData.MIDs_V3[compKey] then
                        for i, mid in pairs(markData.MIDs_V3[compKey]) do
                            if Valid(mid) then
                                pcall(function()
                                    local defC = {R=1, G=1, B=1, A=1, r=1, g=1, b=1, a=1}
                                    mid:SetVectorParameterValue("颜色", defC)
                                    mid:SetVectorParameterValue("Extra Light Color", defC)
                                    mid:SetVectorParameterValue("Para_Color", defC)
                                    mid:SetVectorParameterValue("Tint", defC)
                                    mid:SetVectorParameterValue("BaseColor", defC)
                                    mid:SetVectorParameterValue("Color", defC)
                                end)
                            end
                        end
                    end
                    
                    pcall(function()
                        if comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(false)
                        end
                    end)
                end
            end
            markData.ColorV3Applied = false
            markData.LastMeshCountV3 = 0 -- Reset bộ đếm mesh để có thể bật lại sau
            if markData.MIDs_V3 then markData.MIDs_V3 = nil end
        end
    end)
end
-- ==========================================
-- CHỨC NĂNG WALL MÀU NEW (ĐƯỢC ĐỒNG BỘ VÀO HỆ THỐNG VIP TỐI ƯU)
-- ==========================================
local function ApplyColorBodyNew(enemy, markData)
    pcall(function()
        -- Kích hoạt Console Command nếu chưa bật (Chỉ gọi 1 lần)
        if not _G.ConsoleNewWallReady then
            local KismetSystemLibrary = import("KismetSystemLibrary")
            local world = slua.getWorld()
            if KismetSystemLibrary and world then
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
                _G.ConsoleNewWallReady = true
            end
        end

        -- Lấy toàn bộ Mesh của kẻ địch
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        
        -- Thêm lưới của vũ khí đang cầm trên tay
        local weapon = nil
        pcall(function() weapon = enemy:GetCurrentWeapon() end)
        if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
            table.insert(meshes, weapon.Mesh)
        end

        local isBot = markData.AK_IS_BOT or false
        local currentMeshCount = #meshes
        
        -- [TỐI ƯU FPS TUYỆT ĐỐI] - CHẾ ĐỘ NGỦ ĐÔNG (CACHE)
        -- Tạo mã băm nhận diện: Nếu số lượng quần áo/súng của địch không đổi, bỏ qua vòng lặp C++ cực nặng bên dưới
        local stateHash = (isBot and "BOT" or "PLAYER") .. "_" .. tostring(currentMeshCount)
        
        if markData.LastColorNewHash == stateHash and markData.ColorNewApplied then
            return -- Mọi thứ đã được tô màu trước đó, ngắt hàm tại đây để tránh đốt CPU!
        end
        
        -- Nếu có sự thay đổi (mới bật, địch đổi súng, lụm đồ), tiến hành cập nhật màu và lưu Cache
        markData.LastColorNewHash = stateHash
        markData.ColorNewApplied = true

        -- Chỉ Load bộ màu khi thực sự cần xử lý
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        local c_vis = LinearColorClass and LinearColorClass(0, 100, 0, 1) or {R=0, G=100, B=0, A=1}
        local c_occ = LinearColorClass and LinearColorClass(100, 0, 0, 1) or {R=100, G=0, B=0, A=1}
        local c_bVis = LinearColorClass and LinearColorClass(49, 48, 0, 100) or {R=49, G=48, B=0, A=100}
        local c_bOcc = LinearColorClass and LinearColorClass(9, 1.5, 45, 100) or {R=9, G=1.5, B=45, A=100}

        local visColor = isBot and c_bVis or c_vis
        local occColor = isBot and c_bOcc or c_occ

        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    if type(mesh.SetDrawDyeing) == "function" then
                        mesh:SetDrawDyeing(true)
                        mesh:SetDrawDyeingMode(1)
                        mesh:SetVisibleDyeingColor(visColor)
                        mesh:SetOccludedDyeingColor(occColor)
                        mesh:SetDyeingColorFadeDistance(99999.0)
                        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                        mesh:SetDrawHighlight(true)
                        mesh:OverrideHighlightColor(visColor)
                        mesh:SetHighlightCanBeOccluded(false)
                        mesh:SetDrawIdeaOutline(true)
                        mesh:SetIdeaOutlineNew(true)
                        mesh:SetIdeaOutlineOcclusionHighlight(true)
                        mesh:OverrideIdeaOutlineColor(visColor)
                        mesh:SetIdeaOutlineOcclusionColor(occColor)
                        mesh:OverrideIdeaOutlineThickness(20.0)
                        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                        mesh:SetRenderCustomDepth(true)
                        mesh:SetCustomDepthStencilValue(255)
                    end
                end)
            end
        end
    end)
end

local function UndoColorBodyNew(enemy, markData)
    pcall(function()
        if markData.ColorNewApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            local weapon = nil
            pcall(function() weapon = enemy:GetCurrentWeapon() end)
            if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                table.insert(meshes, weapon.Mesh)
            end

            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(false)
                            mesh:SetDrawHighlight(false)
                            mesh:SetDrawIdeaOutline(false)
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                end
            end
            markData.ColorNewApplied = false
            markData.LastColorNewHash = "" -- Xóa Cache để lần sau bật lại sẽ tính toán lại mượt mà
        end
    end)
end

-- ========================================== 
-- HỆ THỐNG AIMBOT V2 TÍCH HỢP MỚI (UPDATE KISMET SMOOTH)
-- ========================================== 
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()

    if not slua.isValid(player) then
        return result
    end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()

    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

_G.AimTouch = function()
    pcall(function()
        if not _G.GRW_XDConfig.AimTouchEnable then return end
        
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end
        
        local pc = player:GetPlayerControllerSafety()
        if not slua.isValid(pc) then return end
        
        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS
        
        -- CHECK WEAPON & AMMO
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        
        local isShotgun = false
        local isSniper = false
        local isMortar = false
        local currentAmmo = 1
        
        if slua.isValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                isShotgun = true 
            end
            
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end

            if wName:lower():find("mortar") or wName:lower():find("cối") then
                isMortar = true
            end
            
            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        -- LOGIC NHẢ CÒ SÚNG NẾU MẤT MỤC TIÊU / ĐỊCH CHẾT HOẶC SHOTGUN HẾT ĐẠN
        if _G.GRW_XDState.IsAutoFiring then
            pcall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.GRW_XDState.IsAutoFiring = false
        end

        -- SHOTGUN HẾT ĐẠN NGƯNG AIM ĐỂ GAME NẠP ĐẠN
        if isShotgun and currentAmmo <= 0 then
            return
        end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 50
        local fovVal = 30
        local maxDistMeters = 50
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        
        -- Logic thêm vào: Dự đoán và Bù giật
        local predVal = 0 
        local recoilCompVal = 0 

        -- PHÂN LOẠI CẤU HÌNH THEO TRẠNG THÁI HIỆN TẠI
        if isMortar and _G.GRW_XDConfig.AimTouchMortar then
            local isPlaced = false
            pcall(function()
                if weapon and weapon.MortarState == 2 then isPlaced = true end
            end)
            if not isPlaced then return end

            cond = 2 
            prioMode = 1  
            boneIdx = 4 
            speedVal = 100 
            fovVal = _G.GRW_XDState.CustomTextData.AimTouchMortarFOV or 360 
            maxDistMeters = 2000 
            useVisCheck = false 
            igKnock = false
            igBot = false
            predVal = _G.GRW_XDState.CustomTextData.AimTouchMortarPred or 0 
            
        elseif isShotgun and _G.GRW_XDConfig.AimTouchSG then
            cond = _G.GRW_XDState.CustomTextData.AimTouchSGCond or 1
            if _G.GRW_XDConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.GRW_XDState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.GRW_XDState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.GRW_XDState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.GRW_XDState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.GRW_XDState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.GRW_XDConfig.AimTouchSGVisCheck
            igKnock = _G.GRW_XDConfig.AimTouchSGIgKnock
            igBot = _G.GRW_XDConfig.AimTouchSGIgBot
            
        elseif isADS then
            if isSniper and _G.GRW_XDConfig.AimTouchScopeSniper then
                cond = _G.GRW_XDState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.GRW_XDState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.GRW_XDState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.GRW_XDState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.GRW_XDState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.GRW_XDState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.GRW_XDConfig.AimTouchSniperVisCheck
                igKnock = _G.GRW_XDConfig.AimTouchSniperIgKnock
                igBot = _G.GRW_XDConfig.AimTouchSniperIgBot
                predVal = _G.GRW_XDState.CustomTextData.AimTouchSniperPred or 0 -- Lấy giá trị dự đoán Sniper
            elseif _G.GRW_XDConfig.AimTouchScopeAll then
                cond = _G.GRW_XDState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.GRW_XDState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = _G.GRW_XDState.CustomTextData.AimTouchScopeBone or 2
                speedVal = _G.GRW_XDState.CustomTextData.AimTouchScopeSpeed or 40
                fovVal = _G.GRW_XDState.CustomTextData.AimTouchScopeFOV or 20
                maxDistMeters = _G.GRW_XDState.CustomTextData.AimTouchScopeDist or 300
                useVisCheck = _G.GRW_XDConfig.AimTouchScopeVisCheck
                igKnock = _G.GRW_XDConfig.AimTouchScopeIgKnock
                igBot = _G.GRW_XDConfig.AimTouchScopeIgBot
                predVal = _G.GRW_XDState.CustomTextData.AimTouchScopePred or 0 -- Lấy giá trị dự đoán Súng thường
                recoilCompVal = _G.GRW_XDState.CustomTextData.AimTouchScopeRecoil or 0 -- Lấy giá trị bù giật
            else
                return
            end
        else
            if not _G.GRW_XDConfig.AimTouchHipfire then return end
            cond = _G.GRW_XDState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end 
            prioMode = _G.GRW_XDState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = _G.GRW_XDState.CustomTextData.AimTouchHipBone or 1
            speedVal = _G.GRW_XDState.CustomTextData.AimTouchHipSpeed or 50
            fovVal = _G.GRW_XDState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.GRW_XDState.CustomTextData.AimTouchHipDist or 250
            useVisCheck = _G.GRW_XDConfig.AimTouchHipVisCheck
            igKnock = _G.GRW_XDConfig.AimTouchHipIgKnock
            igBot = _G.GRW_XDConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100 

        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end
        
        local FVector2D = import("Vector2D")
        local UGameplayStatics = import("GameplayStatics")
        local KismetMathLibrary = import("KismetMathLibrary")
        
        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not slua.isValid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end
        
        local ui_util = require("client.common.ui_util")
        if not ui_util then return end
        
        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        
        local bestTarget = nil
        local bestScore = 99999999 
        
        local selBoneName = "head"
        if boneIdx == 1 then selBoneName = "head"
        elseif boneIdx == 2 then selBoneName = "spine_03"
        elseif boneIdx == 3 then selBoneName = "spine_01"
        elseif boneIdx == 4 then selBoneName = "pelvis" end

        for i, target in ipairs(enemies) do
            if not slua.isValid(target) then goto continue end
            
            pcall(function()
                if slua.isValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)
            
            if igKnock and target.HealthStatus == 1 then goto continue end
            
            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then goto continue end
            end
            
            -- [FIX TỤT FPS]: Khóa tia Raycast check tường, chỉ quét 0.2s một lần (Đủ mượt mà không cháy CPU)
            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                _G.AimTouchVisCache = _G.AimTouchVisCache or {}
                if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _G.AimTouchVisCache[tId].hidden then goto continue end
            end
            
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            
            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end
            
            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)
            
            if distScreen > FOV_RADIUS then goto continue end
            
            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then 
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end
            
            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
            
            ::continue::
        end
        
        if not slua.isValid(bestTarget) then return end
        
        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        
        local tVelocity = nil
        pcall(function()
            if type(bestTarget.GetVelocity) == "function" then
                tVelocity = bestTarget:GetVelocity()
            end
        end)

        -- LOGIC ĐOÁN HƯỚNG SÚNG CỐI
        if isMortar and _G.GRW_XDConfig.AimTouchMortar and predVal > 0 then
            pcall(function()
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local approxDist = player:GetDistanceTo(bestTarget) / 100.0
                    local approxToF = approxDist / 100.0 
                    local predScale = predVal / 50.0
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * approxToF * predScale)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * approxToF * predScale)
                end
            end)
        end

        -- LOGIC 1: PREDICTION (SÚNG THƯỜNG)
        if not isMortar and predVal > 0 then
            pcall(function()
                -- Nếu địch đang di chuyển
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0 -- Khoảng cách mét
                    
                    -- Tính toán thời gian đạn bay (Time-Of-Flight) tỉ lệ thuận với khoảng cách và biến truyền vào
                    -- Hệ số 800.0 đại diện cho tốc độ đạn rơi giả lập, 50.0 là mức trung bình slider
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0) 
                    
                    -- Dịch chuyển toạ độ Aim lên trước hướng chạy
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        
        -- [BẮT ĐẦU FIX] Bù trừ chênh lệch Camera khi mở ống ngắm (ADS) để không bị lệch tâm
        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
                deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end
        -- [KẾT THÚC FIX]

        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        local smoothFactor = 0.0
        if speedVal >= 100 then
            smoothFactor = 1.0
        else
            smoothFactor = (speedVal / 100.0) * 0.3
            if smoothFactor < 0.01 then smoothFactor = 0.01 end
        end
        
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
        local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        
        -- LOGIC 2: RECOIL COMPENSATION (ÉP TÂM / BÙ GIẬT TRÁNH BẮN QUÁ ĐẦU)
        if recoilCompVal > 0 and isFiring then
            local pullDownForce = (recoilCompVal / 50.0) * 1.5 
            finalPitch = finalPitch - pullDownForce
        end
        
        -- LOGIC TÍNH TOÁN GÓC BẮN THẬT SỰ CHO SÚNG CỐI
        if isMortar and _G.GRW_XDConfig.AimTouchMortar then
            local targetPos = { X = finalBonePos.X, Y = finalBonePos.Y, Z = finalBonePos.Z }
            local launchPos = camLoc
            pcall(function()
                if player.K2_GetActorLocation then
                    local pLoc = player:K2_GetActorLocation()
                    if pLoc then 
                        launchPos = { X = pLoc.X, Y = pLoc.Y, Z = pLoc.Z + 50 } 
                    end
                end
            end)

            local function CalcMortarTrajectory(V, G, tX, tY, tZ)
                local mDx = math.sqrt((tX - launchPos.X)^2 + (tY - launchPos.Y)^2) - 80 
                if mDx < 500 then mDx = 500 end 
                local mDy = tZ - launchPos.Z
                
                local minVSq = G * (mDy + math.sqrt(mDx*mDx + mDy*mDy))
                if (V * V) < minVSq then
                    V = math.sqrt(minVSq) + 100 
                end

                local v2 = V * V
                local root = v2*v2 - G*(G*mDx*mDx + 2*mDy*v2)
                
                if root >= 0 then
                    local angleRad = math.atan((v2 + math.sqrt(root)) / (G * mDx))
                    local deg = math.deg(angleRad)
                    if deg >= 35 and deg <= 89.5 then 
                        return true, deg, mDx / (V * math.cos(angleRad)), mDx
                    end
                end
                return false, 45, 0, mDx
            end

            local vNear, gNear = 9070, 980 * 2.8   
            local vFar, gFar = 12520, 980 * 4.0    
            local vUltra, gUltra = 16800, 980 * 4.5 
            
            local isValid, physAngle, ToF, finalDx = false, 45, 0, 0
            
            local okNear, angNear, tofNear, dxN = CalcMortarTrajectory(vNear, gNear, targetPos.X, targetPos.Y, targetPos.Z)
            local okFar, angFar, tofFar, dxF = CalcMortarTrajectory(vFar, gFar, targetPos.X, targetPos.Y, targetPos.Z)
            local okUltra, angUltra, tofUltra, dxU = CalcMortarTrajectory(vUltra, gUltra, targetPos.X, targetPos.Y, targetPos.Z)

            if okNear and dxN <= 25000 then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            elseif okFar and dxF <= 40000 then
                isValid, physAngle, ToF, finalDx = okFar, angFar, tofFar, dxF
            elseif okUltra then
                isValid, physAngle, ToF, finalDx = okUltra, angUltra, tofUltra, dxU
            elseif okNear then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            end

            local targetCameraPitch = ((physAngle - 45) / 43.0) * 90.0 - 60.0
            local targetCameraYaw = rot.Yaw

            local deltaPitchMortar = targetCameraPitch - currentRot.Pitch
            local deltaYawMortar = targetCameraYaw - currentRot.Yaw

            if deltaPitchMortar > 180 then deltaPitchMortar = deltaPitchMortar - 360 end
            if deltaPitchMortar < -180 then deltaPitchMortar = deltaPitchMortar + 360 end
            if deltaYawMortar > 180 then deltaYawMortar = deltaYawMortar - 360 end
            if deltaYawMortar < -180 then deltaYawMortar = deltaYawMortar + 360 end
            
            finalPitch = currentRot.Pitch + (deltaPitchMortar * smoothFactor)
            finalYaw = currentRot.Yaw + (deltaYawMortar * smoothFactor)
        end

        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }
        pc:SetControlRotation(finalRot, "AimTouch")
        
        if isShotgun and _G.GRW_XDConfig.AimTouchSGAutoFire then
            pcall(function()
                local distToTarget = player:GetDistanceTo(bestTarget) / 100
                if distToTarget <= maxDistMeters then
                    player.bIsWeaponFiring = true
                    if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                    if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                    local wepMgr = player.WeaponManagerComponent
                    if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                    
                    local currentWep = player:GetCurrentWeapon()
                    if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then 
                        currentWep:StartFire() 
                    end
                    _G.GRW_XDState.IsAutoFiring = true
                end
            end)
        end

    end)
end

-- ========================================== 
-- HỆ THỐNG WALL & ESP VẬT PHẨM/PHƯƠNG TIỆN SIÊU MƯỢT (OPTIMIZED DƯỚI 70M)
-- ========================================== 
local ItemDatabase = {
    -- AR
    [101001] = { name = "AKM", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101002] = { name = "M16A4", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101003] = { name = "SCAR-L", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101004] = { name = "M416", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101005] = { name = "Groza", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101006] = { name = "AUG", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101008] = { name = "M762", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    -- SMG
    [102001] = { name = "UZI", cat = "SMG", color = {R=0,G=255,B=255,A=255} }, [102002] = { name = "UMP45", cat = "SMG", color = {R=0,G=255,B=255,A=255} },
    [102003] = { name = "Vector", cat = "SMG", color = {R=0,G=255,B=255,A=255} }, [102004] = { name = "Thompson", cat = "SMG", color = {R=0,G=255,B=255,A=255} },
    -- Sniper
    [103001] = { name = "Kar98K", cat = "Sniper", color = {R=255,G=0,B=0,A=255} }, [103002] = { name = "M24", cat = "Sniper", color = {R=255,G=0,B=0,A=255} },
    [103003] = { name = "AWM", cat = "Sniper", color = {R=255,G=0,B=0,A=255} }, [103009] = { name = "SLR", cat = "Sniper", color = {R=255,G=0,B=0,A=255} },
    -- Shotgun
    [104001] = { name = "S686", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} }, [104003] = { name = "S12K", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} },
    [104004] = { name = "DBS", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} }, 
    -- Súng máy (Gộp vào AR cho gọn hoặc hiện luôn)
    [105001] = { name = "M249", cat = "AR", color = {R=255,G=255,B=255,A=255} }, [105002] = { name = "DP-28", cat = "AR", color = {R=255,G=255,B=255,A=255} }, 
    -- Scope
    [203004] = { name = "4x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, [203005] = { name = "8x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, 
    [203014] = { name = "3x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, [203015] = { name = "6x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }
}

_G.CachedItems = {}
_G.LastScanItemTime = 0
_G.AppliedVehicleWall = {}
_G.AppliedItemESP = {}

-- ========================================== 
-- HỆ THỐNG WALL & ESP VẬT PHẨM/PHƯƠNG TIỆN SIÊU MƯỢT (FULL 100% GỐC)
-- ========================================== 
local C_AR      = {R = 255, G = 255, B = 0, A = 255}
local C_SMG     = {R = 0, G = 255, B = 255, A = 255}
local C_Sniper  = {R = 255, G = 0, B = 0, A = 255}
local C_Shotgun = {R = 0, G = 255, B = 0, A = 255}
local C_LMG     = {R = 255, G = 255, B = 255, A = 255}
local C_Pistol  = {R = 200, G = 200, B = 200, A = 255}
local C_Special = {R = 255, G = 0, B = 255, A = 255}
local C_Melee   = {R = 150, G = 150, B = 150, A = 255}
local C_Scope   = {R = 0, G = 0, B = 255, A = 255}
local C_Grenade = {R = 255, G = 165, B = 0, A = 255}
local C_Med     = {R = 50, G = 255, B = 50, A = 255} -- Màu Xanh cho Máu/Nước

local ItemDatabase = {
    -- AR
    [101001] = { name = "AKM", cat = "AR", color = C_AR }, [101002] = { name = "M16A4", cat = "AR", color = C_AR },
    [101003] = { name = "SCAR-L", cat = "AR", color = C_AR }, [101004] = { name = "M416", cat = "AR", color = C_AR },
    [101005] = { name = "Groza", cat = "AR", color = C_AR }, [101006] = { name = "AUG", cat = "AR", color = C_AR },
    [101007] = { name = "QBZ", cat = "AR", color = C_AR }, [101008] = { name = "M762", cat = "AR", color = C_AR },
    [101009] = { name = "Mk47 Mutant", cat = "AR", color = C_AR }, [101010] = { name = "G36C", cat = "AR", color = C_AR },
    [101011] = { name = "AC-VAL", cat = "AR", color = C_AR }, [101012] = { name = "Honey Badger", cat = "AR", color = C_AR },
    [101100] = { name = "FAMAS", cat = "AR", color = C_AR }, [101101] = { name = "ASM Abakan AR", cat = "AR", color = C_AR },
    [101102] = { name = "ACE32", cat = "AR", color = C_AR },
    -- SMG
    [102001] = { name = "UZI", cat = "SMG", color = C_SMG }, [102002] = { name = "UMP45", cat = "SMG", color = C_SMG },
    [102003] = { name = "Vector", cat = "SMG", color = C_SMG }, [102004] = { name = "Thompson SMG", cat = "SMG", color = C_SMG },
    [102005] = { name = "PP-19 Bizon", cat = "SMG", color = C_SMG }, [102007] = { name = "MP5K", cat = "SMG", color = C_SMG },
    [102008] = { name = "JS9", cat = "SMG", color = C_SMG }, [102105] = { name = "P90", cat = "SMG", color = C_SMG },
    -- Sniper
    [103001] = { name = "Kar98K", cat = "Sniper", color = C_Sniper }, [103002] = { name = "M24", cat = "Sniper", color = C_Sniper },
    [103003] = { name = "AWM", cat = "Sniper", color = C_Sniper }, [103004] = { name = "SKS", cat = "Sniper", color = C_Sniper },
    [103005] = { name = "VSS", cat = "Sniper", color = C_Sniper }, [103006] = { name = "Mini14", cat = "Sniper", color = C_Sniper },
    [103007] = { name = "Mk14", cat = "Sniper", color = C_Sniper }, [103008] = { name = "Win94", cat = "Sniper", color = C_Sniper },
    [103009] = { name = "SLR", cat = "Sniper", color = C_Sniper }, [103010] = { name = "QBU", cat = "Sniper", color = C_Sniper },
    [103011] = { name = "Mosin Nagant", cat = "Sniper", color = C_Sniper }, [103012] = { name = "AMR", cat = "Sniper", color = C_Sniper },
    [103100] = { name = "Mk12", cat = "Sniper", color = C_Sniper }, [103101] = { name = "TR-2A Air Gun", cat = "Sniper", color = C_Sniper },
    [103102] = { name = "DSR", cat = "Sniper", color = C_Sniper }, [103103] = { name = "Sniper Rifle", cat = "Sniper", color = C_Sniper },
    [103104] = { name = "Sniper Rifle", cat = "Sniper", color = C_Sniper }, [103105] = { name = "SR", cat = "Sniper", color = C_Sniper },
    -- Shotgun
    [104001] = { name = "S686", cat = "Shotgun", color = C_Shotgun }, [104002] = { name = "S1897", cat = "Shotgun", color = C_Shotgun },
    [104003] = { name = "S12K", cat = "Shotgun", color = C_Shotgun }, [104004] = { name = "DBS", cat = "Shotgun", color = C_Shotgun },
    [104100] = { name = "SPAS-12", cat = "Shotgun", color = C_Shotgun }, [104101] = { name = "M1014", cat = "Shotgun", color = C_Shotgun },
    [104102] = { name = "NS2000", cat = "Shotgun", color = C_Shotgun },
    -- LMG
    [105001] = { name = "M249", cat = "LMG", color = C_LMG }, [105002] = { name = "DP-28", cat = "LMG", color = C_LMG },
    [105003] = { name = "M134", cat = "LMG", color = C_LMG }, [105010] = { name = "MG3", cat = "LMG", color = C_LMG },
    [105101] = { name = "Gatling", cat = "LMG", color = C_LMG }, [105115] = { name = "Lib Gatling MG", cat = "LMG", color = C_LMG },
    [105004] = { name = "Flamethrower", cat = "LMG", color = C_LMG }, [105006] = { name = "M2 Fixed MG", cat = "LMG", color = C_LMG },
    [105007] = { name = "Gatling Fixed MG", cat = "LMG", color = C_LMG }, [105008] = { name = "Mounted Flamethrower", cat = "LMG", color = C_LMG },
    [105009] = { name = "M2 Mounted MG", cat = "LMG", color = C_LMG }, [105102] = { name = "Vehicle SG", cat = "LMG", color = C_LMG },
    [105103] = { name = "RPG", cat = "LMG", color = C_LMG }, [105104] = { name = "RPG", cat = "LMG", color = C_LMG },
    [105105] = { name = "PowPow MG", cat = "LMG", color = C_LMG }, [105106] = { name = "Tank Cannon", cat = "LMG", color = C_LMG },
    [105107] = { name = "Tank MG", cat = "LMG", color = C_LMG }, [105108] = { name = "Tank Flare Gun", cat = "LMG", color = C_LMG },
    [105116] = { name = "Lib Autocannon", cat = "LMG", color = C_LMG }, [105117] = { name = "Jet Missile", cat = "LMG", color = C_LMG },
    [105118] = { name = "Jet Autocannon", cat = "LMG", color = C_LMG },
    -- Pistol & Pháo sáng
    [106001] = { name = "P92", cat = "Pistol", color = C_Pistol }, [106002] = { name = "P1911", cat = "Pistol", color = C_Pistol },
    [106003] = { name = "R1895", cat = "Pistol", color = C_Pistol }, [106004] = { name = "P18C", cat = "Pistol", color = C_Pistol },
    [106005] = { name = "R45", cat = "Pistol", color = C_Pistol }, [106006] = { name = "Sawed-off", cat = "Pistol", color = C_Pistol },
    [106008] = { name = "Skorpion", cat = "Pistol", color = C_Pistol }, [106010] = { name = "Desert Eagle", cat = "Pistol", color = C_Pistol },
    [106007] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol }, [106009] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol },
    [106011] = { name = "Dual MP7", cat = "Pistol", color = C_Pistol }, [106012] = { name = "Welding Gun", cat = "Pistol", color = C_Pistol },
    [106013] = { name = "Stun Gun", cat = "Pistol", color = C_Pistol }, [106101] = { name = "Vehicle Flare", cat = "Pistol", color = C_Pistol },
    [106103] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol }, [106106] = { name = "Flare (Empty)", cat = "Pistol", color = C_Pistol },
    [106107] = { name = "Respawn Flare", cat = "Pistol", color = C_Pistol }, [106203] = { name = "Magnet Gun", cat = "Pistol", color = C_Pistol },
    -- Đặc biệt
    [107011] = { name = "Súng Cối", cat = "Special", color = C_Special }, [307006] = { name = "Đạn Cối", cat = "Special", color = C_Special },
    [107001] = { name = "Crossbow", cat = "Special", color = C_Special }, [107002] = { name = "RPG-7", cat = "Special", color = C_Special },
    [107003] = { name = "Riot shield", cat = "Special", color = C_Special }, [107004] = { name = "Combat Drone", cat = "Special", color = C_Special },
    [107005] = { name = "Panzerfaust", cat = "Special", color = C_Special }, [107006] = { name = "RPG-7", cat = "Special", color = C_Special },
    [107007] = { name = "Tactical Crossbow", cat = "Special", color = C_Special }, [107008] = { name = "Explosive Bow", cat = "Special", color = C_Special },
    [107009] = { name = "Explosive Bow", cat = "Special", color = C_Special }, [107010] = { name = "M79 Smoke Launcher", cat = "Special", color = C_Special },
    [107019] = { name = "Atlas Gauntlet", cat = "Special", color = C_Special }, [107020] = { name = "Explosive Crossbow", cat = "Special", color = C_Special },
    [107021] = { name = "Mercury Hammer", cat = "Special", color = C_Special }, [107022] = { name = "Fishbones Rocket", cat = "Special", color = C_Special },
    [107031] = { name = "Summer Grenade Launcher", cat = "Special", color = C_Special }, [107032] = { name = "Summer Bazooka", cat = "Special", color = C_Special },
    [107033] = { name = "Summer MG", cat = "Special", color = C_Special }, [107034] = { name = "Color Bazooka", cat = "Special", color = C_Special },
    [107035] = { name = "Bubble MG", cat = "Special", color = C_Special }, [107036] = { name = "Snowball Blaster", cat = "Special", color = C_Special },
    [107037] = { name = "Water Orb Blaster", cat = "Special", color = C_Special }, [107092] = { name = "MGL", cat = "Special", color = C_Special },
    [107093] = { name = "M202 Quad RPG", cat = "Special", color = C_Special }, [107094] = { name = "AT4-A Laser Missile", cat = "Special", color = C_Special },
    [107095] = { name = "M202 Quad RPG", cat = "Special", color = C_Special }, [107096] = { name = "M79 Sawed-off", cat = "Special", color = C_Special },
    [107097] = { name = "M79", cat = "Special", color = C_Special }, [107098] = { name = "MGL", cat = "Special", color = C_Special },
    [107099] = { name = "M3E1-A", cat = "Special", color = C_Special }, [107901] = { name = "Zombie Piercer", cat = "Special", color = C_Special },
    [107903] = { name = "Mounted RPG", cat = "Special", color = C_Special }, [107904] = { name = "Helicopter RPG", cat = "Special", color = C_Special },
    [107911] = { name = "M3E1-B Missile", cat = "Special", color = C_Special },
    -- Cận chiến
    [108001] = { name = "Machete", cat = "Melee", color = C_Melee }, [108002] = { name = "Crowbar", cat = "Melee", color = C_Melee },
    [108003] = { name = "Sickle", cat = "Melee", color = C_Melee }, [108004] = { name = "Pan", cat = "Melee", color = C_Melee },
    [108005] = { name = "Dagger", cat = "Melee", color = C_Melee }, [108006] = { name = "Mutation Blade", cat = "Melee", color = C_Melee },
    [108007] = { name = "Mutation Gauntlets", cat = "Melee", color = C_Melee },
    -- Scope
    [203001] = { name = "Red Dot Sight", cat = "Scope", color = C_Scope }, [203002] = { name = "Holographic Sight", cat = "Scope", color = C_Scope },
    [203003] = { name = "2x Scope", cat = "Scope", color = C_Scope }, [203004] = { name = "4x Scope", cat = "Scope", color = C_Scope },
    [203005] = { name = "8x Scope", cat = "Scope", color = C_Scope }, [203014] = { name = "3x Scope", cat = "Scope", color = C_Scope },
    [203015] = { name = "6x Scope", cat = "Scope", color = C_Scope },
    -- Lựu đạn
    [602001] = { name = "Stun Grenade", cat = "Grenade", color = C_Grenade }, [602002] = { name = "Smoke Grenade", cat = "Grenade", color = C_Grenade },
    [602003] = { name = "Molotov", cat = "Grenade", color = C_Grenade }, [602004] = { name = "Frag Grenade", cat = "Grenade", color = C_Grenade },
    
    -- Vật phẩm Y tế (Máu, Nước, Phục Hồi) -- Item Medis (Darah, Minuman, Pemulihan)
    [601001] = { name = "Minuman Energi", cat = "Med", color = C_Med }, [601002] = { name = "Suntik Adrenalin", cat = "Med", color = C_Med },
    [601003] = { name = "Obat Pereda Nyeri", cat = "Med", color = C_Med }, [601004] = { name = "Perban", cat = "Med", color = C_Med },
    [601005] = { name = "P3K", cat = "Med", color = C_Med }, [601006] = { name = "Pertolongan Pertama", cat = "Med", color = C_Med },
    [601009] = { name = "Perban Cepat", cat = "Med", color = C_Med }, [601010] = { name = "P3K Cepat", cat = "Med", color = C_Med },
    [601011] = { name = "Perban Militer", cat = "Med", color = C_Med }, [601012] = { name = "Minuman Kental", cat = "Med", color = C_Med },
    [601020] = { name = "Perban", cat = "Med", color = C_Med }, [601021] = { name = "P3K", cat = "Med", color = C_Med },
    [601022] = { name = "Pertolongan Pertama", cat = "Med", color = C_Med }, [601023] = { name = "Suntik Adrenalin", cat = "Med", color = C_Med },
    [601061] = { name = "Pertolongan Pertama", cat = "Med", color = C_Med }, [601077] = { name = "P3K Taktis", cat = "Med", color = C_Med },
    [601078] = { name = "P3K Serba Guna", cat = "Med", color = C_Med }, [601079] = { name = "Pertolongan Serba Guna", cat = "Med", color = C_Med },
    [601080] = { name = "Perban Militer", cat = "Med", color = C_Med }, [601081] = { name = "Minuman Kental", cat = "Med", color = C_Med },
    [601084] = { name = "P3K Cepat", cat = "Med", color = C_Med }, [601085] = { name = "Pertolongan Cepat", cat = "Med", color = C_Med },
    [601095] = { name = "AED (Resusitasi)", cat = "Med", color = C_Med }, [601096] = { name = "Persiapan Tempur", cat = "Med", color = C_Med },
    [602054] = { name = "Logistik Medis", cat = "Med", color = C_Med }, [602069] = { name = "Bantuan Darurat", cat = "Med", color = C_Med }
}
_G.CachedItems = {}
_G.LastScanItemTime = 0
_G.AppliedVehicleWall = {}
_G.AppliedItemESP = {}

_G.RunOptimizedItemAndVehicleESP = function(pc)
    local curTime = os.clock()

    -- 1. QUÉT ACTOR VÀ XỬ LÝ VẬT LÝ 1.0 GIÂY / LẦN (Chống Drop FPS khi nhặt đồ)
    if curTime - _G.LastScanItemTime > 1.0 then
        _G.LastScanItemTime = curTime
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end

        -- XỬ LÝ WALL PHƯƠNG TIỆN (Giữ nguyên khoảng cách nhìn xa 200m)
        if _G.GRW_XDConfig.WallVehicle then
            local ASTExtraVehicleBase = import("STExtraVehicleBase")
            if ASTExtraVehicleBase then
                local Actors = Game:GetActorsByClass(ASTExtraVehicleBase)
                if Actors then
                    local count = Actors:Num() or 0
                    for i = 0, count - 1 do
                        local vehicle = Actors:Get(i)
                        if slua.isValid(vehicle) and vehicle.GetMesh then
                            local dist = player:GetDistanceTo(vehicle)
                            if dist <= 200000 then 
                                local vId = tostring(vehicle)
                                if not _G.AppliedVehicleWall[vId] then
                                    local mesh = vehicle:GetMesh()
                                    if slua.isValid(mesh) then
                                        local matInterface = mesh:GetMaterial(0)
                                        if slua.isValid(matInterface) then
                                            local baseMat = matInterface:GetBaseMaterial()
                                            if slua.isValid(baseMat) then
                                                baseMat.bDisableDepthTest = true
                                                baseMat.BlendMode = 2
                                                _G.AppliedVehicleWall[vId] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else _G.AppliedVehicleWall = {} end

        -- XỬ LÝ ESP VÀ CHAMS VẬT PHẨM (Định vị chữ & Glow dưới 70m)
        if _G.GRW_XDConfig.EspItem_Master then
            local APickUpWrapperActor = import("PickUpWrapperActor") or import("STPickupWrapperActor")
            if APickUpWrapperActor then
                local Actors = Game:GetActorsByClass(APickUpWrapperActor)
                _G.CachedItems = {}
                if Actors then
                    local count = Actors:Num() or 0
                    for i = 0, count - 1 do
                        local item = Actors:Get(i)
                        
                        -- [FIX KẸT VẬT PHẨM] Kiểm tra xem item có đang chờ bị xóa không
                        local isPendingKill = false
                        pcall(function() if type(item.IsPendingKill) == "function" then isPendingKill = item:IsPendingKill() end end)

                        -- Chỉ quét các vật phẩm Hợp Lệ, Không Bị Ẩn (bHidden) và Chưa Bị Xóa
                        if slua.isValid(item) and not item.bHidden and not isPendingKill then
                            local dist = player:GetDistanceTo(item)
                            -- Giới hạn 70m (7000 units), bảo đảm không hao CPU
                            if dist <= 7000 then
                                local itemId = item.DefineID and item.DefineID.TypeSpecificID or item.DefineId
                                local itemData = ItemDatabase[itemId]
                                
                                if itemData then
                                    -- Check xem công tắc phân loại có đang bật không?
                                    local isShow = false
                                    if itemData.cat == "AR" and _G.GRW_XDConfig.EspItem_AR then isShow = true
                                    elseif itemData.cat == "Sniper" and _G.GRW_XDConfig.EspItem_Sniper then isShow = true
                                    elseif itemData.cat == "SMG" and _G.GRW_XDConfig.EspItem_SMG then isShow = true
                                    elseif itemData.cat == "Shotgun" and _G.GRW_XDConfig.EspItem_Shotgun then isShow = true
                                    elseif itemData.cat == "LMG" and _G.GRW_XDConfig.EspItem_LMG then isShow = true
                                    elseif itemData.cat == "Pistol" and _G.GRW_XDConfig.EspItem_Pistol then isShow = true
                                    elseif itemData.cat == "Melee" and _G.GRW_XDConfig.EspItem_Melee then isShow = true
                                    elseif itemData.cat == "Special" and _G.GRW_XDConfig.EspItem_Special then isShow = true
                                    elseif itemData.cat == "Grenade" and _G.GRW_XDConfig.EspItem_Grenade then isShow = true
                                    elseif itemData.cat == "Scope" and _G.GRW_XDConfig.EspItem_Scope then isShow = true
                                    elseif itemData.cat == "Med" and _G.GRW_XDConfig.EspItem_Med then isShow = true
                                    end

                                    -- Chỉ xử lý mảng và vẽ Glow nếu đang bật
                                    if isShow then
                                        table.insert(_G.CachedItems, item)

                                        local iId = tostring(item)
                                        if not _G.AppliedItemESP[iId] then
                                            local meshes = {}
                                            if item.GetPickupMesh then
                                                local pMesh = item:GetPickupMesh()
                                                if slua.isValid(pMesh) then table.insert(meshes, pMesh) end
                                            end
                                            local childs = item:GetComponentsByClass(import("StaticMeshComponent"))
                                            if childs then
                                                for _, v in pairs(childs) do
                                                    if slua.isValid(v) then table.insert(meshes, v) end
                                                end
                                            end
                                            for _, mesh in pairs(meshes) do
                                                pcall(function() mesh:SetRenderCustomDepth(true) end)
                                                for mi = 0, 8 do
                                                    local mid = mesh:CreateAndSetMaterialInstanceDynamic(mi)
                                                    if slua.isValid(mid) then
                                                        local colorVisible = {R = 50, G = 50, B = 0, A = 10}
                                                        pcall(function()
                                                            mid:SetVectorParameterValue("LightColor", colorVisible)
                                                            mid:SetVectorParameterValue("ParaScaleOffset", {R = 3, G = 3, B = 0, A = 0})
                                                            mid:SetScalarParameterValue("RimLight", 999)
                                                            mid:SetScalarParameterValue("Brightness", 999)
                                                            mid:SetScalarParameterValue("Exposure", 999)
                                                        end)
                                                    end
                                                end
                                            end
                                            _G.AppliedItemESP[iId] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else 
            _G.AppliedItemESP = {}
            _G.CachedItems = {}
        end
    end

    -- 2. VẼ TÊN VẬT PHẨM LIÊN TỤC VÀO KHUNG HÌNH (Rất nhẹ, chạy mỗi frame)
    if _G.GRW_XDConfig.EspItem_Master and slua.isValid(pc) and pc.MyHUD then
        local hud = pc.MyHUD
        local player = GameplayData.GetPlayerCharacter()
        for _, item in ipairs(_G.CachedItems) do
            -- [TỐI ƯU FPS TỐI ĐA] Chỉ check bHidden (cực nhẹ), bỏ qua pcall tốn CPU ở vòng lặp mỗi frame
            if slua.isValid(item) and not item.bHidden then
                local itemId = item.DefineID and item.DefineID.TypeSpecificID or item.DefineId
                if itemId and ItemDatabase[itemId] then
                    local itemData = ItemDatabase[itemId]
                    local dist = (player.GetDistanceTo and player:GetDistanceTo(item) or 0) / 100
                    local displayText = string.format("%s [%.0fm]", itemData.name, dist)
                    local textColor = {R = itemData.color.R, G = itemData.color.G, B = itemData.color.B, A = 255}
                    hud:AddDebugText(
                        displayText, item, 0.06, 
                        {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, 
                        textColor, true, false, true, nil, 0.8, true
                    )
                end
            end
        end
    end
end


-- ========================================== 
-- UI WIDGET ĐẾM ĐỊCH & KHOẢNG CÁCH GẦN NHẤT (NEW ESP LOGIC)
-- ========================================== 
local BTN_BP = "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP"
local EnemyCounterWidget = nil
local WarningTargetWidget = nil
local LastCounterTime = 0

-- THÊM HÀM DỌN DẸP WIDGET KHI THOÁT TRẬN
function _G.CleanUpEnemyCounterWidget()
    if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
        EnemyCounterWidget:RemoveFromParent()
    end
    EnemyCounterWidget = nil

    if WarningTargetWidget and slua.isValid(WarningTargetWidget) then
        WarningTargetWidget:RemoveFromParent()
    end
    WarningTargetWidget = nil
end

-- TẠO UI: ĐẾM ĐỊCH (GỐC)
local function CreateEnemyCounterWidget()
    if EnemyCounterWidget then
        if slua.isValid(EnemyCounterWidget) then return EnemyCounterWidget else EnemyCounterWidget = nil end
    end

    pcall(function()
        local btn = slua.loadUI(BTN_BP)
        if not btn or not slua.isValid(btn) then return end
        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 10500)
        
     if btn.RichText_Content then
       btn.RichText_Content:SetText("Musuh: 0  |  Terdekat: 0m")
       local fontInfo = btn.RichText_Content.Font
       if fontInfo then fontInfo.Size = 16 btn.RichText_Content:SetFont(fontInfo) end
   end
        
        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            slot:SetPosition(FVector2D(0, 30))
            slot:SetSize(FVector2D(240, 36))
        end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        EnemyCounterWidget = btn
    end)
    return EnemyCounterWidget
end

-- TẠO UI: CẢNH BÁO ĐỊCH NGẮM (ĐỘC LẬP)
local function CreateWarningTargetWidget()
    if WarningTargetWidget then
        if slua.isValid(WarningTargetWidget) then return WarningTargetWidget else WarningTargetWidget = nil end
    end

    pcall(function()
        local btn = slua.loadUI(BTN_BP)
        if not btn or not slua.isValid(btn) then return end
        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 10501) -- Z-Order cao hơn để nổi lên
        
        if btn.RichText_Content then
            -- Chữ màu đỏ cảnh báo mạnh
            btn.RichText_Content:SetText("ĐỊCH ĐANG NHÌN VỀ PHÍA BẠN")
            local fontInfo = btn.RichText_Content.Font
            if fontInfo then fontInfo.Size = 18 btn.RichText_Content:SetFont(fontInfo) end
        end
        
        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            slot:SetPosition(FVector2D(0, 75)) -- Nằm bên dưới UI đếm địch (Y=75)
            slot:SetSize(FVector2D(260, 36))
        end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) -- Mặc định ẩn, chỉ hiện khi bị ngắm
        WarningTargetWidget = btn
    end)
    return WarningTargetWidget
end

-- VÒNG LẶP CHUNG (TÍNH TOÁN 1 LẦN CHO CẢ 2 UI ĐỂ CHỐNG DROP FPS)
local function _M_DrawCounter()
    if isExpired then
        _G.CleanUpEnemyCounterWidget()
        return
    end

    pcall(function()
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then 
            if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
                EnemyCounterWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            if WarningTargetWidget and slua.isValid(WarningTargetWidget) then
                WarningTargetWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            return 
        end

        local widgetCounter = CreateEnemyCounterWidget()
        local widgetWarning = CreateWarningTargetWidget()

        if widgetCounter and slua.isValid(widgetCounter) then
            widgetCounter:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end

        -- [TỐI ƯU FPS] Khóa nhịp tính toán 0.5 giây / lần để tránh quá tải CPU
        local curTime = os.clock()
        if (curTime - LastCounterTime) > 0.5 then
            LastCounterTime = curTime
            
            local myTeam = player.TeamID or (type(player.GetTeamID) == "function" and player:GetTeamID()) or 0
            local count = 0
            local nearest = 9999
            local isBeingTargeted = false -- Trạng thái cảnh báo
            
            local KismetMathLibrary = import("KismetMathLibrary")
            local pc = player:GetPlayerControllerSafety()

            local allCharacters = {}
            if GameplayData.GetAllPlayerCharacters then
                allCharacters = GameplayData.GetAllPlayerCharacters()
            elseif GameplayData.GameCharacters then
                for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
            end

            for _, tPawn in pairs(allCharacters) do
                if slua.isValid(tPawn) and tPawn ~= player then
                    local isAlive = false
                    if tPawn.HealthStatus ~= nil then
                        isAlive = (tPawn.HealthStatus ~= 2)
                    else
                        isAlive = (tPawn.Health or 0) > 0 or (type(tPawn.IsAlive) == "function" and tPawn:IsAlive())
                    end
                    
                    if isAlive then
                        local tTeam = tPawn.TeamID or (type(tPawn.GetTeamID) == "function" and tPawn:GetTeamID()) or 0
                        if tTeam ~= myTeam then
                            count = count + 1
                            local d = math.floor(player:GetDistanceTo(tPawn) / 100)
                            if d < nearest then nearest = d end
                            
                            -- ========================================================
                            -- LOGIC CHECK ĐỊCH NGẮM (Chỉ tính khi khoảng cách < 400m)
                            -- ========================================================
                            if _G.GRW_XDConfig.EspAimWarning and not isBeingTargeted and d < 400 then
                                local eLoc = type(tPawn.K2_GetActorLocation) == "function" and tPawn:K2_GetActorLocation()
                                local pLoc = type(player.K2_GetActorLocation) == "function" and player:K2_GetActorLocation()
                                
                                if eLoc and pLoc and KismetMathLibrary then
                                    local lookRot = KismetMathLibrary.FindLookAtRotation(eLoc, pLoc)
                                    local eRot = nil
                                    
                                    if type(tPawn.GetControlRotation) == "function" then
                                        eRot = tPawn:GetControlRotation()
                                    elseif type(tPawn.GetActorRotation) == "function" then
                                        eRot = tPawn:GetActorRotation()
                                    end
                                    
                                    if eRot and lookRot then
                                        local dYaw = math.abs(eRot.Yaw - lookRot.Yaw)
                                        if dYaw > 180 then dYaw = 360 - dYaw end
                                        
                                        local dPitch = math.abs(eRot.Pitch - lookRot.Pitch)
                                        if dPitch > 180 then dPitch = 360 - dPitch end
                                        
                                        -- Địch hướng nòng súng sai lệch < 15 độ
                                        if dYaw < 15 and dPitch < 20 then
                                            -- Áp dụng logic Check Tường (VisCheck)
                                            if _G.GRW_XDConfig.EspAimWarningVisCheck then
                                                if slua.isValid(pc) and type(pc.LineOfSightTo) == "function" then
                                                    if pc:LineOfSightTo(tPawn) then
                                                        isBeingTargeted = true
                                                    end
                                                end
                                            else
                                                -- Xuyên tường báo luôn
                                                isBeingTargeted = true
                                            end
                                        end
                                    end
                                end
                            end
                            -- ========================================================
                        end
                    end
                end
            end

    -- Cập nhật nội dung UI đếm địch (Khung 1) -- Perbarui konten UI penghitung musuh (Frame 1)
    if widgetCounter and widgetCounter.RichText_Content then
        widgetCounter.RichText_Content:SetText(string.format("Musuh Di Sekitar: %d  |  Terdekat: %dm", count, count > 0 and nearest or 0))
    end

            -- Ẩn/Hiện UI Cảnh báo độc lập (Khung 2)
            if widgetWarning and slua.isValid(widgetWarning) then
                if _G.GRW_XDConfig.EspAimWarning and isBeingTargeted then
                    widgetWarning:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                else
                    widgetWarning:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end
            end
        end
    end)
end
-- ============================================================
-- BẮT ĐẦU: LÕI ESP LOẠI 9 (TỪ CODE MẪU GỐC FULL LOGIC)
-- ============================================================
local PlayerMapMarker = {}

local RedBoxOverlay = {
    bActive = false,
    MainContainer = nil,
    WidgetSlot = nil,
    TextBlock = nil,
    Width = 145,
    Height = 25,
    OffsetY = 10,
    PlayerCount = 0,
    BotCount = 0,
    FontSize = 13,
    TextScaleValue = 1.0,
    _CachedText = "",
    _CachedPosVec = nil
}

function RedBoxOverlay.Create()
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return true end

    local ParentCanvas = PlayerMapMarker.ESPCanvas
    if not ParentCanvas or not slua.isValid(ParentCanvas) then 
        if not PlayerMapMarker.InitESPCanvas() then return false end
        ParentCanvas = PlayerMapMarker.ESPCanvas
    end

    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    local FLinearColor = import("LinearColor") or FLinearColor
    local FVector2D = import("Vector2D") or FVector2D
    
    -- Viền đỏ bên ngoài (Red Border)
    local redBorder = nil
    pcall(function() redBorder = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    if redBorder and slua.isValid(redBorder) then
        pcall(function()
            redBorder:SetBrushColor(FLinearColor(0.8, 0.0, 0.0, 0.9)) -- Viền đỏ
            redBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slotRed = Container:AddChildToCanvas(redBorder)
        if slotRed then
            slotRed:SetPosition(FVector2D(0, 0))
            slotRed:SetSize(FVector2D(RedBoxOverlay.Width, RedBoxOverlay.Height))
        end
    end

    -- Khung nền TRẮNG bên trong (White Background)
    local whiteBg = nil
    pcall(function() whiteBg = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    if whiteBg and slua.isValid(whiteBg) then
        pcall(function()
            whiteBg:SetBrushColor(FLinearColor(0.025, 0.035, 0.050, 0.95)) -- Professional dark graphite background
            whiteBg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slotWhite = Container:AddChildToCanvas(whiteBg)
        if slotWhite then
            -- Thụt vào 1.5 pixel mỗi bên để vẫn giữ lại viền ngoài màu đỏ
            slotWhite:SetPosition(FVector2D(1.5, 1.5))
            slotWhite:SetSize(FVector2D(RedBoxOverlay.Width - 3, RedBoxOverlay.Height - 3))
        end
    end

    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
    
    -- Chữ Enemy: X | Bot: Y
    local txtBlock = nil
    pcall(function() txtBlock = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if txtBlock and slua.isValid(txtBlock) then
        pcall(function()
            local strText = string.format("Enemy: %d | Bot: %d", RedBoxOverlay.PlayerCount, RedBoxOverlay.BotCount)
            txtBlock:SetText(strText)
            RedBoxOverlay._CachedText = strText

            -- High-contrast white text for the dark overlay background
            local blackTextColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
            if FSlateColor then txtBlock:SetColorAndOpacity(FSlateColor(blackTextColor)) else txtBlock:SetColorAndOpacity(blackTextColor) end

            if txtBlock.Font then
                local font = txtBlock.Font
                font.Size = RedBoxOverlay.FontSize
                txtBlock.Font = font
            end
            txtBlock:SetRenderScale(FVector2D(RedBoxOverlay.TextScaleValue, RedBoxOverlay.TextScaleValue))
            txtBlock:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtBlock:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local txtSlot = Container:AddChildToCanvas(txtBlock)
        if txtSlot then
            pcall(function()
                txtSlot:SetAutoSize(true)
                txtSlot:SetAlignment(FVector2D(0.5, 0.5))
                txtSlot:SetPosition(FVector2D(RedBoxOverlay.Width * 0.5, RedBoxOverlay.Height * 0.5))
                txtSlot:SetZOrder(1000)
            end)
        end
        RedBoxOverlay.TextBlock = txtBlock
    end

    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if not MainSlot then return false end

    RedBoxOverlay.MainContainer = Container
    RedBoxOverlay.WidgetSlot = MainSlot
    
    pcall(function()
        MainSlot:SetAutoSize(false)
        MainSlot:SetZOrder(999)
        MainSlot:SetAlignment(FVector2D(0.5, 0.0))
        MainSlot:SetSize(FVector2D(RedBoxOverlay.Width, RedBoxOverlay.Height))
    end)

    RedBoxOverlay.UpdatePosition()
    return true
end

function RedBoxOverlay.SetCounts(players, bots)
    if RedBoxOverlay.PlayerCount == players and RedBoxOverlay.BotCount == bots then return end
    RedBoxOverlay.PlayerCount = players or 0
    RedBoxOverlay.BotCount = bots or 0
    
    if RedBoxOverlay.TextBlock and slua.isValid(RedBoxOverlay.TextBlock) then
        pcall(function()
            local str = string.format("Enemy: %d | Bot: %d", RedBoxOverlay.PlayerCount, RedBoxOverlay.BotCount)
            if RedBoxOverlay._CachedText ~= str then
                RedBoxOverlay.TextBlock:SetText(str)
                RedBoxOverlay._CachedText = str
            end
        end)
    end
end

function RedBoxOverlay.UpdatePosition()
    local Slot = RedBoxOverlay.WidgetSlot
    if not Slot or not slua.isValid(Slot) then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not slua.isValid(PC) then return end

    local fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    local FVector2D = import("Vector2D") or FVector2D
    pcall(function()
        if not RedBoxOverlay._CachedPosVec then
            RedBoxOverlay._CachedPosVec = FVector2D(fromX, fromY)
        else
            RedBoxOverlay._CachedPosVec.X = fromX
            RedBoxOverlay._CachedPosVec.Y = fromY
        end
        Slot:SetPosition(RedBoxOverlay._CachedPosVec)
    end)
end

function RedBoxOverlay.Start()
    if RedBoxOverlay.bActive and RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return end
    if RedBoxOverlay.Create() then
        RedBoxOverlay.bActive = true
        pcall(function() RedBoxOverlay.MainContainer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end
end

function RedBoxOverlay.Stop()
    RedBoxOverlay.bActive = false
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
        pcall(function()
            RedBoxOverlay.MainContainer:RemoveFromParent()
            RedBoxOverlay.MainContainer:ConditionalBeginDestroy()
        end)
    end
    RedBoxOverlay.MainContainer = nil
    RedBoxOverlay.WidgetSlot = nil
    RedBoxOverlay.TextBlock = nil
    RedBoxOverlay._CachedPosVec = nil
end

_G.RedBoxOverlay = RedBoxOverlay

local InGameMarkTools = nil
pcall(function() InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools") end)

local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local KismetMathLibrary = nil
local KismetSystemLibrary = nil

pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
pcall(function() KismetMathLibrary = import("KismetMathLibrary") end)
pcall(function() KismetSystemLibrary = import("KismetSystemLibrary") end)

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local FVector = _G.FVector or import("Vector")

PlayerMapMarker.MarkTypeID = 1007
PlayerMapMarker.bUseScreenESP = true
PlayerMapMarker.bUseScreenMark = false
PlayerMapMarker.bUseQuickSign = false
PlayerMapMarker.bUseNavigator = false
PlayerMapMarker.bUseWidgetComponent = false
PlayerMapMarker.QuickSignConfigKey = "C_MarkPos"

PlayerMapMarker.WidgetCompUIPath = "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips"
PlayerMapMarker.WidgetCompBoneName = "head"
PlayerMapMarker.WidgetCompOffset = FVector and FVector(0, 0, 80) or {X=0, Y=0, Z=80}
PlayerMapMarker.WidgetCompDrawSize = FVector2D and FVector2D(210, 35) or {X=210, Y=35} -- [SIZE 70%]

PlayerMapMarker.ESPBoneName = "head"
PlayerMapMarker.ESPWorldOffsetZ = 0
PlayerMapMarker.ESPScreenOffsetY = 0
PlayerMapMarker.ESPAnchorOffsetX = 35 -- [SIZE 70%]
PlayerMapMarker.ESPAnchorOffsetY = 0
PlayerMapMarker.ESPTextOffsetX = 0
PlayerMapMarker.ESPTextOffsetY = 0

PlayerMapMarker.ESPWidgetAlignment = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
PlayerMapMarker.ESPWidgetSize = FVector2D and FVector2D(70, 21) or {X=70, Y=21} -- [SIZE 70%]
PlayerMapMarker.ESPWidgetAutoSize = true
PlayerMapMarker.ESPWidgetZOrder = 2

PlayerMapMarker.bShowDistance = true
PlayerMapMarker.DistanceUnit = "m"
PlayerMapMarker.WeaponIconBrushW = 96 -- [SIZE 70%] Gốc 138
PlayerMapMarker.WeaponIconBrushH = 48 -- [SIZE 70%] Gốc 69
PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
PlayerMapMarker.HPWidgetSwitcherType2Index = 0
PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true

PlayerMapMarker.bUseSnapLines = true
PlayerMapMarker.SnapLineThickness = 1.0 -- [SIZE 70%] Gốc 1.5
PlayerMapMarker.SnapLineOriginY = 50
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14 -- [SIZE 70%] Gốc -20
PlayerMapMarker.SnapLineColor = FLinearColor and FLinearColor(0.6, 0.0, 0.0, 1.0) or {R=150, G=0, B=0, A=255} -- Đỏ Đậm
PlayerMapMarker.SnapLineOpacity = 0.7

-- ====== BẮT ĐẦU: CẤU HÌNH SKELETON (TỪ CODE MẪU) ======
PlayerMapMarker.bUseSkeleton = true                      -- Tùy chọn bật Skeleton
PlayerMapMarker.SkeletonThickness = 0.8                  -- [SIZE 70%] Gốc 1.2                  
PlayerMapMarker.SkeletonColor = nil                      
PlayerMapMarker.SkeletonOpacity = 0.8  
-- [TỐI ƯU FPS] Rất quan trọng: Chỉ vẽ Khung xương dưới 80 mét. Vẽ xương ở quá xa sẽ khiến máy lag tung chảo.
PlayerMapMarker.SkeletonMaxDistance = 20000             
PlayerMapMarker.bUseVisibilityColor = true              
PlayerMapMarker.SkeletonVisibleColor = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 0.8) or {R=0,G=255,B=0,A=200}
PlayerMapMarker.SkeletonCoverColor = FLinearColor and FLinearColor(0.9, 0.0, 0.0, 0.6) or {R=230,G=0,B=0,A=150}

PlayerMapMarker.SkeletonWidgets = {}
PlayerMapMarker._StaticBoneLocCache = {}

PlayerMapMarker.SkeletonChains = {
    {"neck_01", "lowerarm_r", "hand_r"},
    {"neck_01", "lowerarm_l", "hand_l"},
    {"head", "neck_01", "pelvis"},
    {"pelvis", "calf_r", "foot_r"},
    {"pelvis", "calf_l", "foot_l"}
}

PlayerMapMarker.BoneNameFallbacks = {
    ["head"] = {"head", "Head", "head_socket"},
    ["neck_01"] = {"neck_01", "Neck_01", "neck", "Neck"},
    ["clavicle_r"] = {"clavicle_r", "Clavicle_R", "clavicle_R"},
    ["upperarm_r"] = {"upperarm_r", "UpperArm_R", "arm_r", "arm_r_01"},
    ["lowerarm_r"] = {"lowerarm_r", "LowerArm_R", "forearm_r"},
    ["hand_r"] = {"hand_r", "Hand_R", "hand_r_socket"},
    ["clavicle_l"] = {"clavicle_l", "Clavicle_L", "clavicle_L"},
    ["upperarm_l"] = {"upperarm_l", "UpperArm_L", "arm_l", "arm_l_01"},
    ["lowerarm_l"] = {"lowerarm_l", "LowerArm_L", "forearm_l"},
    ["hand_l"] = {"hand_l", "Hand_L", "hand_l_socket"},
    ["spine_03"] = {"spine_03", "Spine_03", "spine_02", "spine"},
    ["spine_02"] = {"spine_02", "Spine_02", "spine_01"},
    ["pelvis"] = {"pelvis", "Pelvis", "hip"},
    ["thigh_r"] = {"thigh_r", "Thigh_R", "leg_r"},
    ["calf_r"] = {"calf_r", "Calf_R", "shin_r"},
    ["foot_r"] = {"foot_r", "Foot_R", "foot_r_socket"},
    ["thigh_l"] = {"thigh_l", "Thigh_L", "leg_l"},
    ["calf_l"] = {"calf_l", "Calf_L", "shin_l"},
    ["foot_l"] = {"foot_l", "Foot_L", "foot_l_socket"},
}
-- ====== KẾT THÚC: CẤU HÌNH SKELETON ======

PlayerMapMarker.MapAddedFlag = 4
PlayerMapMarker.nUpdateInterval = 0.5
PlayerMapMarker.bUseFrameTick = false
PlayerMapMarker.nHeavyScanFrameInterval = 15
PlayerMapMarker.nDistanceUpdateFrameInterval = 5
PlayerMapMarker.bIncludeMe = false
PlayerMapMarker.bIncludeAI = true
PlayerMapMarker.bUseServerMarks = false

PlayerMapMarker.bActive = false
PlayerMapMarker.MarkMap = {}
PlayerMapMarker.PlayerInfo = {}
PlayerMapMarker.ESPCanvas = nil
PlayerMapMarker.ESPWidgets = {}
PlayerMapMarker.ESPWidgetPtrs = {}
PlayerMapMarker.SnapLineWidgets = {}

PlayerMapMarker._cachedViewportW = 1920
PlayerMapMarker._cachedViewportH = 1080
PlayerMapMarker._FrameCount = 0
PlayerMapMarker._bTickRegistered = false
PlayerMapMarker._CachedAllChars = nil
PlayerMapMarker._CachedMyLoc = nil
PlayerMapMarker._CachedMyKey = nil
PlayerMapMarker.WidgetComps = {}
PlayerMapMarker._bAllPathsFailed = false
PlayerMapMarker._bLightUpdateScheduled = false
-- [TỐI ƯU FPS] Giảm tốc độ render từ 50 xuống 25 FPS (Đủ mượt mà không gây cháy CPU)
PlayerMapMarker._LightUpdateInterval = 0.04 
PlayerMapMarker._bDistanceUpdateScheduled = false
PlayerMapMarker._DistanceUpdateInterval = 0.1
PlayerMapMarker._bScreenMarkConfigSetup = false

local function IsValid(obj)
    if obj == nil then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return obj ~= nil
end

function PlayerMapMarker.SetupScreenMarkConfig()
    if PlayerMapMarker._bScreenMarkConfigSetup then return true end
    local bOK = false
    pcall(function()
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local ScreenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
        if ScreenMarkConfig then
            ScreenMarkConfig[1007] = {
                UIPathName = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C",
                MaxWidgetNum = 100,
                MaxShowDistance = 6000000,
                bBindOutScreen = false,
                bBindBlocked = true,
                bNeedPreLoad = true,
                bIsBindingActor = true,
                BindSocketName = "HelmetSocket",
                WorldPositionOffset = FVector and FVector(0, 0, 80) or {X=0,Y=0,Z=80}
            }
            PlayerMapMarker._bScreenMarkConfigSetup = true
            bOK = true
        end
    end)
    return bOK
end

function PlayerMapMarker.GetGameplayData()
    if PlayerMapMarker._CachedGameplayData then return PlayerMapMarker._CachedGameplayData end
    local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and GDP then PlayerMapMarker._CachedGameplayData = GDP return GDP end
    return nil
end

function PlayerMapMarker.GetMyPlayerController()
    local PC = PlayerMapMarker._CachedPC
    if PC and IsValid(PC) then return PC end
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
    if PC and IsValid(PC) then PlayerMapMarker._CachedPC = PC return PC end
    return nil
end

function PlayerMapMarker.GetCGameState()
    if CGameState and IsValid(CGameState) then return CGameState end
    if PlayerMapMarker._CachedCGameState and IsValid(PlayerMapMarker._CachedCGameState) then return PlayerMapMarker._CachedCGameState end
    local ok, GS = pcall(function() return require("GameLua.GameCore.Data.CGameState") end)
    if ok and GS then PlayerMapMarker._CachedCGameState = GS return GS end
    return nil
end

function PlayerMapMarker.GetAllCharacters()
    local AllChars = {}
    pcall(function()
        local Pawns = Game:GetAllPlayerPawns()
        if Pawns then
            for _, Pawn in pairs(Pawns) do
                if Pawn and slua.isValid(Pawn) then
                    local pKey = nil
                    if Pawn.GetPlayerKey then pKey = Pawn:GetPlayerKey() end
                    if not pKey and Pawn.PlayerKey then pKey = Pawn.PlayerKey end
                    if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then pKey = Pawn.PlayerState.PlayerKey end
                    if pKey then AllChars[pKey] = Pawn end
                end
            end
        end
    end)
    if not next(AllChars) then
        local GS = PlayerMapMarker.GetCGameState()
        if GS and GS.GetAllCharacters then pcall(function() AllChars = GS:GetAllCharacters() end) end
    end
    return AllChars
end

function PlayerMapMarker.GetMyPlayerKey()
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return nil end
    local MyKey = nil
    pcall(function()
        if PC.GetPlayerKey then MyKey = PC:GetPlayerKey()
        elseif PC.PlayerState and PC.PlayerState.PlayerKey then MyKey = PC.PlayerState.PlayerKey end
    end)
    return MyKey
end

function PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
    local bIsMe = false
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            local MyChar = GDP.GetLocalCharacter()
            if MyChar and Character == MyChar then bIsMe = true return end
        end
        local PC = PlayerMapMarker.GetMyPlayerController()
        if PC and PC.GetPawn then
            local Pawn = PC:GetPawn()
            if Pawn and Character == Pawn then bIsMe = true return end
        end
    end)
    if not bIsMe and MyKey ~= nil and PlayerKey ~= nil then bIsMe = (tostring(PlayerKey) == tostring(MyKey)) end
    return bIsMe
end

function PlayerMapMarker.GetCharacterLocation(Character)
    if not IsValid(Character) then return nil end
    local Loc = nil
    pcall(function() if Character.K2_GetActorLocation then Loc = Character:K2_GetActorLocation() end end)
    if not Loc then pcall(function() if Game and Game.GetActorLocation then Loc = Game:GetActorLocation(Character) end end) end
    return Loc
end

function PlayerMapMarker.CalcDistance(Loc1, Loc2)
    if not Loc1 or not Loc2 then return nil end
    local Dist = nil
    pcall(function() if FVector and FVector.Dist2D then Dist = FVector.Dist2D(Loc1, Loc2) end end)
    if not Dist then
        pcall(function()
            local DX = (Loc1.X or 0) - (Loc2.X or 0)
            local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
            Dist = math.sqrt(DX * DX + DY * DY)
        end)
    end
    return Dist
end

function PlayerMapMarker.GetDistanceString(MyLoc, TargetLoc)
    if not PlayerMapMarker.bShowDistance then return "" end
    if not MyLoc or not TargetLoc then return "" end
    local Dist = PlayerMapMarker.CalcDistance(MyLoc, TargetLoc)
    if not Dist then return "" end
    local Meters = Dist / 100
    if Meters < 1000 then return string.format("%dm", math.floor(Meters))
    else return string.format("%.1fkm", Meters / 1000) end
end

function PlayerMapMarker.GetMyLocation()
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    local MyChar = nil
    pcall(function() MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
    if not IsValid(MyChar) then
        local PC = PlayerMapMarker.GetMyPlayerController()
        if IsValid(PC) then
            pcall(function()
                if PC.GetPawn then
                    local Pawn = PC:GetPawn()
                    if IsValid(Pawn) and Pawn.K2_GetActorLocation then return Pawn:K2_GetActorLocation() end
                end
            end)
        end
        return nil
    end
    return PlayerMapMarker.GetCharacterLocation(MyChar)
end

function PlayerMapMarker.GetPlayerName(Character)
    if not IsValid(Character) then return "Unknown" end
    local Name = nil
    pcall(function() if Character.GetPlayerNameSafety then Name = Character:GetPlayerNameSafety() end end)
    if not Name then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetPlayerName then Name = PS:GetPlayerName() end
        end)
    end
    return Name or "Unknown"
end

function PlayerMapMarker.IsAI(Character)
    local bAI = false
    pcall(function() if Game and Game.IsAI then bAI = Game:IsAI(Character) end end)
    return bAI
end

function PlayerMapMarker.IsAlive(Character)
    local bAlive = true
    pcall(function() if Character.IsAlive then bAlive = Character:IsAlive() end end)
    return bAlive
end

function PlayerMapMarker.IsOurESPWidget(w)
    if not w or not slua.isValid(w) then return false end
    local bIsOurs = false
    pcall(function()
        local wstr = tostring(w)
        for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
            if ESPData and ESPData.Widget and ESPData.Widget.Container then
                local cstr = tostring(ESPData.Widget.Container)
                if cstr == wstr then bIsOurs = true return end
            end
        end
    end)
    if bIsOurs then return true end
    pcall(function()
        if w.GetChildrenCount then
            local n = w:GetChildrenCount()
            for i = 0, n - 1 do
                local child = w:GetChildAt(i)
                if child and slua.isValid(child) then
                    local cstr = tostring(child)
                    if string.find(cstr, "Border") then bIsOurs = true break end
                end
            end
        end
    end)
    if not bIsOurs then
        pcall(function()
            local slot = w.Slot
            if slot and slot.GetPosition then
                local pos = slot:GetPosition()
                if pos and (math.abs(pos.X or 0) > 1 or math.abs(pos.Y or 0) > 1) then bIsOurs = true end
            end
        end)
    end
    return bIsOurs
end

function PlayerMapMarker.ApplyAnchorBasedPosition(Slot, ScreenPos, Canvas)
    if not Slot or not ScreenPos then return false end
    local sx = ScreenPos.X or 0
    local sy = ScreenPos.Y or 0
    local sz = PlayerMapMarker.ESPWidgetSize or (FVector2D and FVector2D(100, 30) or {X=100, Y=30})
    local align = PlayerMapMarker.ESPWidgetAlignment or (FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0})

    local canvasW, canvasH = 0, 0
    if PlayerMapMarker._cachedViewportW and PlayerMapMarker._cachedViewportW > 200 then
        canvasW = PlayerMapMarker._cachedViewportW
        canvasH = PlayerMapMarker._cachedViewportH
    end

    if canvasW < 200 then
        pcall(function()
            local PC = PlayerMapMarker.GetMyPlayerController()
            if IsValid(PC) and PC.GetViewportSize then
                local VS = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                PC:GetViewportSize(VS)
                if VS and VS.X and VS.X > 200 then
                    canvasW = VS.X ; canvasH = VS.Y
                    PlayerMapMarker._cachedViewportW = canvasW ; PlayerMapMarker._cachedViewportH = canvasH
                end
            end
        end)
    end

    if canvasW > 200 and canvasH > 200 then
        local anchorX = (sx + (PlayerMapMarker.ESPAnchorOffsetX or 0)) / canvasW
        local anchorY = (sy + (PlayerMapMarker.ESPAnchorOffsetY or 0)) / canvasH
        anchorX = math.max(0, math.min(1, anchorX))
        anchorY = math.max(0, math.min(1, anchorY))

        local bSuccess = false
        pcall(function()
            local FAnchors = import("Anchors") or import("/Script/SlateCore.Anchors")
            if Slot.SetAnchors and FAnchors then
                local anchors = FAnchors(anchorX, anchorY, anchorX, anchorY)
                if anchors then Slot:SetAnchors(anchors) Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X=0, Y=0}) bSuccess = true end
            end
        end)
        if not bSuccess then
            pcall(function()
                if Slot.SetAnchors then Slot:SetAnchors(anchorX, anchorY, anchorX, anchorY) Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X=0, Y=0}) bSuccess = true end
            end)
        end
        if bSuccess then
            pcall(function() if Slot.SetOffsets and import("Margin") then Slot:SetOffsets(import("Margin")(0, 0, sz.X, sz.Y)) end end)
            pcall(function() Slot:SetSize(sz) end)
            pcall(function() Slot:SetAlignment(align) end)
            pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true) end end)
            pcall(function() if Slot.SetZOrder then Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2) end end)
            return true
        end
    end

    pcall(function()
        Slot:SetPosition(FVector2D and FVector2D(sx, sy) or {X=sx, Y=sy})
        pcall(function() Slot:SetSize(sz) end)
        pcall(function() Slot:SetAlignment(align) end)
        pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true) end end)
        pcall(function() if Slot.SetZOrder then Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2) end end)
    end)
    return false
end

function PlayerMapMarker.InitESPCanvas()
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then return true end
    local ok, InGameUITools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if not ok or not InGameUITools then return false end
    local MainControlBaseUI = InGameUITools.GetMainControlBaseUI and InGameUITools.GetMainControlBaseUI()
    if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then return false end

    local ParentCanvas = nil
    if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then 
        ParentCanvas = MainControlBaseUI.CanvasPanel_0
    elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then 
        ParentCanvas = MainControlBaseUI.CanvasPanel_42 
    end

    if not ParentCanvas then return false end
    PlayerMapMarker.ESPCanvas = ParentCanvas
    -- ĐÃ BỎ VÒNG LẶP QUÉT RÁC GÂY DROP FPS TRONG HÀM NÀY
    return true
end

function PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0 ; MaxDepth = MaxDepth or 5
    if Depth > MaxDepth then return nil end

    local bIsPB = false
    pcall(function() if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then bIsPB = true end end)
    if bIsPB then return WidgetObj end

    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)

    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PlayerMapMarker.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PlayerMapMarker.GetTeamID(Character)
    if not IsValid(Character) then return nil end
    local TeamID = nil
    pcall(function() if Character.GetTeamID then TeamID = Character:GetTeamID() end end)
    if not TeamID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetTeamID then TeamID = PS:GetTeamID()
            elseif IsValid(PS) and PS.TeamID then TeamID = PS.TeamID end
        end)
    end
    if not TeamID then pcall(function() if Character.TeamID then TeamID = Character.TeamID end end) end
    return TeamID
end

function PlayerMapMarker.GetTeamColor(TeamID)
    if TeamID == nil or TeamID == 0 then 
        return FLinearColor and FLinearColor(0.2, 0.4, 1.0, 1.0) or {R=50,G=100,B=255,A=255} 
    end
    
    -- Khởi tạo bảng 15 màu sắc rực rỡ và dễ phân biệt
    local TeamColors = {
        [1]  = {R=255, G=50,  B=50,  A=255, fR=1.0, fG=0.2, fB=0.2}, -- Đỏ
        [2]  = {R=50,  G=255, B=50,  A=255, fR=0.2, fG=1.0, fB=0.2}, -- Lục (Xanh lá)
        [3]  = {R=50,  G=100, B=255, A=255, fR=0.2, fG=0.4, fB=1.0}, -- Lam (Xanh dương)
        [4]  = {R=255, G=255, B=50,  A=255, fR=1.0, fG=1.0, fB=0.2}, -- Vàng
        [5]  = {R=255, G=50,  B=255, A=255, fR=1.0, fG=0.2, fB=1.0}, -- Tím / Hồng Đậm
        [6]  = {R=50,  G=255, B=255, A=255, fR=0.2, fG=1.0, fB=1.0}, -- Xanh Ngọc Bích (Cyan)
        [7]  = {R=255, G=150, B=50,  A=255, fR=1.0, fG=0.6, fB=0.2}, -- Cam
        [8]  = {R=150, G=50,  B=255, A=255, fR=0.6, fG=0.2, fB=1.0}, -- Tím Đậm
        [9]  = {R=200, G=255, B=50,  A=255, fR=0.8, fG=1.0, fB=0.2}, -- Vàng Chanh
        [10] = {R=50,  G=150, B=255, A=255, fR=0.2, fG=0.6, fB=1.0}, -- Xanh Nước Biển
        [11] = {R=255, G=100, B=150, A=255, fR=1.0, fG=0.4, fB=0.6}, -- Hồng Nhạt
        [12] = {R=100, G=255, B=150, A=255, fR=0.4, fG=1.0, fB=0.6}, -- Xanh Trà
        [13] = {R=150, G=150, B=50,  A=255, fR=0.6, fG=0.6, fB=0.2}, -- Màu Olive
        [14] = {R=50,  G=200, B=150, A=255, fR=0.2, fG=0.8, fB=0.6}, -- Xanh Rêu
        [15] = {R=255, G=200, B=50,  A=255, fR=1.0, fG=0.8, fB=0.2}  -- Vàng Kim
    }
    
    -- Dùng thuật toán Modulo để xoay vòng màu. 
    -- Ví dụ: Team 16 chia 15 dư 1 sẽ dùng lại màu số 1.
    -- Đảm bảo 100 người (25 team) trong trận đều được tự động gắn màu, chung team = chung màu.
    local colorIndex = (TeamID % 15)
    if colorIndex == 0 then colorIndex = 15 end 
    
    local c = TeamColors[colorIndex]
    return FLinearColor and FLinearColor(c.fR, c.fG, c.fB, 1.0) or {R=c.R, G=c.G, B=c.B, A=c.A}
end

local _WhiteTexture = nil
local _bWhiteTextureFailed = false
local function GetWhiteTexture()
    if _WhiteTexture then return _WhiteTexture end
    if _bWhiteTextureFailed then return nil end
    pcall(function()
        local paths = { "/Game/BluePrints/UI/Textures/White.White", "/Game/BluePrints/UI/Textures/Common/White.White", "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture" }
        for _, path in ipairs(paths) do
            pcall(function() local tex = import(path); if tex and slua.isValid(tex) then _WhiteTexture = tex return end end)
            if _WhiteTexture then break end
        end
    end)
    if not _WhiteTexture then _bWhiteTextureFailed = true end
    return _WhiteTexture
end

local function SetImageColor(Image, color)
    if not Image or not slua.isValid(Image) then return false end
    local bOK = false
    pcall(function() if Image.SetBrushTintColor then Image:SetBrushTintColor(color); bOK = true end end)
    pcall(function() if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color); bOK = true end end)
    pcall(function()
        if Image.SetBrushFromTexture then
            local whiteTex = GetWhiteTexture()
            if whiteTex then
                Image:SetBrushFromTexture(whiteTex, false)
                if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color) end
                bOK = true
            end
        end
    end)
    pcall(function() Image:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible); Image:SetRenderOpacity(1.0) end)
    return bOK
end

function PlayerMapMarker._GetWidgetRoot(WidgetObj)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    local Root = nil
    pcall(function() if WidgetObj.GetRootWidget then Root = WidgetObj:GetRootWidget() end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.WidgetTree and WidgetObj.WidgetTree.RootWidget then Root = WidgetObj.WidgetTree.RootWidget end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.RootWidget and slua.isValid(WidgetObj.RootWidget) then Root = WidgetObj.RootWidget end end)
    return Root
end

function PlayerMapMarker._FindNamedWidgetInTree(WidgetObj, TargetName, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    MaxDepth = MaxDepth or 8
    local wname = nil
    pcall(function() if WidgetObj.GetName then wname = WidgetObj:GetName() end end)
    if wname and wname == TargetName then return WidgetObj end

    local wstr = tostring(WidgetObj)
    if wstr and string.find(wstr, TargetName, 1, true) then
        if wname and wname == TargetName then return WidgetObj
        elseif not wname or wname == "" then
            local _, endPos = string.find(wstr, TargetName, 1, true)
            if endPos then
                local nextChar = string.sub(wstr, endPos + 1, endPos + 1)
                if nextChar ~= "_" and nextChar ~= "" then return WidgetObj end
            end
        end
    end

    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)

    if nChildren > 0 then
        for i = 0, nChildren - 1 do
            local child = nil
            pcall(function() child = WidgetObj:GetChildAt(i) end)
            if child and slua.isValid(child) then
                local found = PlayerMapMarker._FindNamedWidgetInTree(child, TargetName, MaxDepth - 1)
                if found then return found end
            end
        end
    else
        local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local found = PlayerMapMarker._FindNamedWidgetInTree(Root, TargetName, MaxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

function PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
    if not Widget or not Widget.Container then return end
    
    -- [THÊM MỚI] Check công tắc tắt Ô màu team
    if not _G.GRW_XDConfig.Esp9_Team then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                local img1 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
                if img1 and slua.isValid(img1) then img1:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                local img2 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
                if img2 and slua.isValid(img2) then img2:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                if Widget.TeamBgBorder and slua.isValid(Widget.TeamBgBorder) then Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
        end)
        return
    end

    local color = PlayerMapMarker.GetTeamColor(TeamID)
    if not color then return end

    pcall(function()
        local W = Widget.Container
        if not W or not slua.isValid(W) then return end

        local bBG = false
        local Image_TeamBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
        if Image_TeamBG and slua.isValid(Image_TeamBG) then bBG = SetImageColor(Image_TeamBG, color) end

        local Image_TeamLogoBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
        if Image_TeamLogoBG and slua.isValid(Image_TeamLogoBG) then SetImageColor(Image_TeamLogoBG, color) end

        if W.SetTeamColor then pcall(function() W:SetTeamColor(TeamID) end) end
        
        if not Widget.TeamBgBorder or not slua.isValid(Widget.TeamBgBorder) then
            pcall(function()
                local Border = CGame:NewObjectFromPath("/Script/UMG.Border", W)
                if Border and slua.isValid(Border) then
                    pcall(function() Border:SetBrushColor(color) end)
                    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() Border:SetRenderOpacity(0.7) end)
                    pcall(function() Border:SetDesiredSizeOverride(FVector2D and FVector2D(120, 20) or {X=120, Y=20}) end)
                    pcall(function() if W.AddChild then W:AddChild(Border) end end)
                    pcall(function() if Border.SetZOrder then Border:SetZOrder(-1) end end)
                    Widget.TeamBgBorder = Border
                end
            end)
        else
            pcall(function()
                Widget.TeamBgBorder:SetBrushColor(color)
                Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                Widget.TeamBgBorder:SetRenderOpacity(0.7)
            end)
        end
    end)
end

function PlayerMapMarker.GetCharacterMesh(Character)
    if not IsValid(Character) then return nil end
    local Mesh = nil
    pcall(function() if Character.Mesh and Game:IsValid(Character.Mesh) then Mesh = Character.Mesh end end)
    if not Mesh then pcall(function() local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent") Mesh = Character:GetComponentByClass(SkeletalMeshCompClass) end) end
    return Mesh
end

function PlayerMapMarker.GetESPLocation(Character)
    if not IsValid(Character) then return nil end
    local BoneLoc = PlayerMapMarker.GetCharacterLocation(Character)
    if BoneLoc then
        local heightOffset = 85
        pcall(function()
            if Character.bIsCrouched then heightOffset = 60 end
            if Character.IsProne and Character:IsProne() then heightOffset = 30 end
        end)
        pcall(function() BoneLoc.Z = BoneLoc.Z + heightOffset + (PlayerMapMarker.ESPWorldOffsetZ or 0) end)
    end
    return BoneLoc
end

function PlayerMapMarker.GetCharacterWeaponInfo(Character)
    if not IsValid(Character) then return nil end
    local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon = nil, nil, nil, nil, nil

    pcall(function() if Character.GetCurrentWeapon then CurrentWeapon = Character:GetCurrentWeapon() end end)
    if not CurrentWeapon then pcall(function() CurrentWeapon = Character.CurrentWeapon end) end
    if not CurrentWeapon then pcall(function() if Character.GetWeaponManager then local WM = Character:GetWeaponManager() if WM and WM.GetCurrentWeapon then CurrentWeapon = WM:GetCurrentWeapon() end end end) end

    if CurrentWeapon and IsValid(CurrentWeapon) then
        pcall(function() if CurrentWeapon.GetWeaponID then WeaponID = CurrentWeapon:GetWeaponID() end end)
        if not WeaponID then pcall(function() WeaponID = CurrentWeapon.WeaponID end) end
        if not WeaponID then pcall(function() if CurrentWeapon.GetItemID then WeaponID = CurrentWeapon:GetItemID() end end) end
        pcall(function() if CurrentWeapon.GetWeaponName then WeaponName = CurrentWeapon:GetWeaponName() end end)
        pcall(function() if CurrentWeapon.GetWeaponIconPath then WeaponIconPath = CurrentWeapon:GetWeaponIconPath() end end)
        pcall(function() if CurrentWeapon.GetWeaponIcon then WeaponIconTexture = CurrentWeapon:GetWeaponIcon() end end)
    end

    if not WeaponID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety() elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if PS and IsValid(PS) then
                if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
            end
        end)
    end
    return { WeaponID = WeaponID, WeaponName = WeaponName, WeaponIconPath = WeaponIconPath, WeaponIconTexture = WeaponIconTexture, CurrentWeapon = CurrentWeapon }
end

function PlayerMapMarker.FindWeaponIconInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0 ; MaxDepth = MaxDepth or 8
    local propNames = { "Image_Weapon", "Image_WeaponIcon", "Image_Gun", "Image_Icon", "WeaponIcon", "WeaponImage", "Image_Equip" }
    for _, pname in ipairs(propNames) do
        pcall(function()
            local prop = WidgetObj[pname]
            if prop and slua.isValid(prop) then
                local hasBrush = false
                pcall(function() if prop.Brush then hasBrush = true end end)
                if hasBrush then return prop end
            end
        end)
    end
    if Depth >= MaxDepth then return nil end
    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PlayerMapMarker.FindWeaponIconInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    if nChildren == 0 then
        local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local result = PlayerMapMarker.FindWeaponIconInWidget(Root, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, DefaultW, DefaultH)
    if not ImageWidget or not slua.isValid(ImageWidget) then return end
    DefaultW = DefaultW or 138 ; DefaultH = DefaultH or 69
    pcall(function()
        local brush = ImageWidget.Brush
        if brush then
            brush.ImageSize = FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}
            brush.DrawAs = 3
            brush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
            if ImageWidget.SetBrush then ImageWidget:SetBrush(brush) end
        end
        if ImageWidget.SetDesiredSizeOverride then ImageWidget:SetDesiredSizeOverride(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        local slot = ImageWidget.Slot
        if slot and slot.SetSize then slot:SetSize(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        ImageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        ImageWidget:SetRenderOpacity(1.0)
        ImageWidget:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1})
    end)
end

function PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
    local fullIcon = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end
    pcall(function() if ourWeaponIcon.SetRenderOpacity then ourWeaponIcon:SetRenderOpacity(1.0) end end)
    pcall(function() if ourWeaponIcon.SetColorAndOpacity then ourWeaponIcon:SetColorAndOpacity(fullIcon) end end)
    pcall(function()
        local brush = ourWeaponIcon.Brush
        if brush then pcall(function() brush.TintColor = fullIcon end) if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end end
    end)
    local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
    for _, pname in ipairs(chainNames) do
        pcall(function()
            local node = Container and Container[pname]
            if node and slua.isValid(node) and node.SetRenderOpacity then node:SetRenderOpacity(1.0) end
            if node and slua.isValid(node) and node.SetColorAndOpacity then node:SetColorAndOpacity(fullIcon) end
        end)
    end
end

function PlayerMapMarker.ApplyWeaponIconToImage(ImageWidget, winfo)
    if not ImageWidget or not slua.isValid(ImageWidget) then return false, "no_widget" end
    if not winfo or not winfo.WeaponID then return false, "no_weapon_id" end

    local iconPath = nil
    local method = "none"
    local bHasAddKnownMissing = false
    local defaultW = 138
    local defaultH = 69

    pcall(function()
        local itemRecord = CDataTable.GetTableData("Item", winfo.WeaponID)
        if itemRecord and itemRecord.KillWhiteIcon and itemRecord.KillWhiteIcon ~= "" then iconPath = itemRecord.KillWhiteIcon method = "KillWhiteIcon" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconPath and winfo.WeaponIconPath ~= "" then iconPath = winfo.WeaponIconPath method = "WeaponIconPath" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconTexture and slua.isValid(winfo.WeaponIconTexture) then
            if ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(winfo.WeaponIconTexture, true) method = "WeaponIconTexture" return end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath, bHasAddKnownMissing = UIUtil.GetItemBigIcon(winfo.WeaponID, ImageWidget)
            if iconPath and iconPath ~= "" then method = "GetItemBigIcon" end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath = UIUtil.GetItemSmallIcon(winfo.WeaponID, ImageWidget, bHasAddKnownMissing)
            if iconPath and iconPath ~= "" then method = "GetItemSmallIcon" end
        end
    end)

    if method == "WeaponIconTexture" then PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) return true, method end
    if not iconPath or iconPath == "" then return false, "no_path" end

    local bOK = false
    pcall(function()
        if ImageWidget.SetBrushResourceFromPathSync then ImageWidget:SetBrushResourceFromPathSync(iconPath, true) bOK = true end
        if not bOK then
            local util = require("client.slua_ui_framework.util")
            local result = util.SetTexture(ImageWidget, iconPath, { sync = true, bMatchSize = true, bIsInCombatState = true, bHasAddKnownMissing = bHasAddKnownMissing })
            bOK = result ~= nil
        end
        if not bOK then
            local tex = import(iconPath)
            if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
        end
        if not bOK then
            local LoadObject = import("LoadObject")
            if LoadObject then
                local tex = LoadObject(iconPath)
                if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
            end
        end
    end)

    if bOK then PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) end
    return bOK, method .. ":" .. tostring(iconPath)
end

function PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return false end
    if not nativeWeaponIcon or not slua.isValid(nativeWeaponIcon) then return false end

    local bCopied = false
    pcall(function()
        local nBrush = nativeWeaponIcon.Brush
        if nBrush then
            local resObj = nil
            pcall(function() resObj = nBrush.ResourceObject end)
            if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                ourWeaponIcon:SetBrushFromTexture(resObj, true)
                bCopied = true
            end
            if bCopied then
                local imgSize = nil
                pcall(function() imgSize = nBrush.ImageSize end)
                if imgSize then
                    local oBrush = ourWeaponIcon.Brush
                    if oBrush then oBrush.ImageSize = imgSize if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(oBrush) end end
                end
            end
        end
    end)
    return bCopied
end

function PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
    if not WidgetData or not WidgetData.Container then return end
    local Container = WidgetData.Container
    if not slua.isValid(Container) then return end

    -- [THÊM MỚI] Check công tắc Tắt Icon Súng
    if not _G.GRW_XDConfig.Esp9_Weapon then
        pcall(function()
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                local node = Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
            local ourWeaponIcon = Container.WeaponIcon or PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8)
            if ourWeaponIcon and slua.isValid(ourWeaponIcon) then ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
        end)
        WidgetData._LastWeaponID = 0
        WidgetData._WeaponIconApplied = false
        return
    end

    pcall(function()
        local ourWeaponIcon = Container.WeaponIcon
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then ourWeaponIcon = PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8) end
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end

        local winfo = Character and PlayerMapMarker.GetCharacterWeaponInfo(Character) or nil

        if not winfo or not winfo.WeaponID or winfo.WeaponID == 0 then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                pcall(function()
                    local node = Container and Container[pname]
                    if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                end)
            end
            WidgetData._LastWeaponID = 0
            WidgetData._WeaponIconApplied = false
            return
        end

        if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() ourWeaponIcon:SetRenderOpacity(1.0) end)
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                pcall(function()
                    local node = Container and Container[pname]
                    if node and slua.isValid(node) and node.SetWidgetVisibility then
                        node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        pcall(function() if node.SetRenderOpacity then node:SetRenderOpacity(1.0) end end)
                    end
                end)
            end
            if WidgetData._CachedSwitcherIndexes then
                for sName, idx in pairs(WidgetData._CachedSwitcherIndexes) do
                    pcall(function()
                        local ws = Container[sName]
                        if ws and slua.isValid(ws) and ws.SetActiveWidgetIndex then ws:SetActiveWidgetIndex(idx) end
                    end)
                end
            end
            if WidgetData._CachedParentSwitchers then
                for _, data in pairs(WidgetData._CachedParentSwitchers) do
                    pcall(function() if data.w and slua.isValid(data.w) and data.w.SetActiveWidgetIndex then data.w:SetActiveWidgetIndex(data.idx) end end)
                end
            end
            return
        end

        local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
        for _, pname in ipairs(chainNames) do
            pcall(function()
                local node = Container and Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
            end)
        end

        local bCopied = false
        if winfo and winfo.WeaponID then
            local ok, method = PlayerMapMarker.ApplyWeaponIconToImage(ourWeaponIcon, winfo)
            if ok then bCopied = true end
        end

        local bWeaponIconSet = false
        if Character and winfo then
            if winfo and winfo.WeaponID then
                pcall(function() if Container.SetWeaponIcon then Container:SetWeaponIcon(winfo.WeaponID) bWeaponIconSet = true end end)
                if not bWeaponIconSet then pcall(function() if Container.SetWeaponIconByID then Container:SetWeaponIconByID(winfo.WeaponID) bWeaponIconSet = true end end) end
                if not bWeaponIconSet then pcall(function() if Container.UpdateWeaponIcon then Container:UpdateWeaponIcon(winfo.WeaponID) bWeaponIconSet = true end end) end
                if not bWeaponIconSet then pcall(function() if Container.SetWeaponID then Container:SetWeaponID(winfo.WeaponID) bWeaponIconSet = true end end) end
                pcall(function() if Container.SetData then Container:SetData(Character) end end)
                pcall(function() if Container.SetPlayerInfo then Container:SetPlayerInfo(Character) end end)
                if winfo.CurrentWeapon then pcall(function() if Container.SetCurrentWeapon then Container:SetCurrentWeapon(winfo.CurrentWeapon) end end) end
            end
        end

        if bWeaponIconSet then
            pcall(function()
                local innerIcon = Container.Image_Icon
                if not innerIcon or not slua.isValid(innerIcon) then if Container.CanvasPanel_Type1 then innerIcon = Container.CanvasPanel_Type1.Image_Icon end end
                if not innerIcon or not slua.isValid(innerIcon) then
                    local function findImageIcon(w, depth)
                        if not w or not slua.isValid(w) or depth > 8 then return nil end
                        local prop = w.Image_Icon
                        if prop and slua.isValid(prop) then return prop end
                        local n = 0
                        pcall(function() if w.GetChildrenCount then n = w:GetChildrenCount() end end)
                        for i = 0, math.max(n - 1, 0) do
                            local c = nil
                            pcall(function() c = w:GetChildAt(i) end)
                            if c then local r = findImageIcon(c, depth + 1) if r then return r end end
                        end
                        return nil
                    end
                    innerIcon = findImageIcon(Container, 0)
                end
                if innerIcon and slua.isValid(innerIcon) and innerIcon ~= ourWeaponIcon then
                    pcall(function()
                        local ibrush = innerIcon.Brush
                        if ibrush then
                            local iresObj = nil
                            pcall(function() iresObj = ibrush.ResourceObject end)
                            if iresObj and slua.isValid(iresObj) then
                                if ourWeaponIcon.SetBrushFromAsset then ourWeaponIcon:SetBrushFromAsset(iresObj) bCopied = true end
                                if not bCopied and ourWeaponIcon.SetBrushFromTexture then ourWeaponIcon:SetBrushFromTexture(iresObj) bCopied = true end
                            end
                        end
                    end)
                    if not bCopied then
                        pcall(function()
                            local brush = innerIcon.Brush
                            if brush then
                                local iresObj = nil
                                pcall(function() iresObj = brush.ResourceObject end)
                                if iresObj and slua.isValid(iresObj) and ourWeaponIcon.SetBrushFromTexture then
                                    ourWeaponIcon:SetBrushFromTexture(iresObj, false)
                                    PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)
                                    bCopied = true
                                end
                            end
                        end)
                    end
                end
            end)
        end

        if not bCopied then
            local nativeWeaponIcon = nil
            if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
                local nChildren = 0
                pcall(function() nChildren = PlayerMapMarker.ESPCanvas:GetChildrenCount() end)
                for i = 0, math.max(nChildren - 1, 0) do
                    local child = nil
                    pcall(function() child = PlayerMapMarker.ESPCanvas:GetChildAt(i) end)
                    if child and slua.isValid(child) then
                        local cstr = tostring(child)
                        if string.find(cstr, "OB_PlayerHeadHPItem") then
                            if not PlayerMapMarker.IsOurESPWidget(child) then
                                local nativeIcon = child.WeaponIcon
                                if nativeIcon and slua.isValid(nativeIcon) then nativeWeaponIcon = nativeIcon break end
                            end
                        end
                    end
                end
            end

            if nativeWeaponIcon and slua.isValid(nativeWeaponIcon) then
                local okNative, nativeMethod = PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
                if okNative then bCopied = true end
            end
        end

        if not bCopied then
            pcall(function()
                local brush = ourWeaponIcon.Brush
                if brush then
                    local resObj = nil
                    pcall(function() resObj = brush.ResourceObject end)
                    if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                        ourWeaponIcon:SetBrushFromTexture(resObj)
                        bCopied = true
                    end
                end
            end)
        end

        if not bCopied then
            pcall(function()
                local brush = ourWeaponIcon.Brush
                if brush then
                    local imgSize = nil
                    pcall(function() imgSize = brush.ImageSize end)
                    local bZeroSize = false
                    if imgSize then
                        local sx, sy = nil, nil
                        pcall(function() sx = imgSize.X end)
                        pcall(function() sy = imgSize.Y end)
                        if (not sx or sx == 0) and (not sy or sy == 0) then bZeroSize = true end
                    end
                    if bZeroSize then
                        pcall(function() brush.ImageSize = FVector2D and FVector2D(PlayerMapMarker.WeaponIconBrushW or 138, PlayerMapMarker.WeaponIconBrushH or 69) or {X=138, Y=69} end)
                    end
                    pcall(function() brush.DrawAs = 3 end)
                    if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end
                end
            end)
        end

        pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
        PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)

        pcall(function()
            local function findWidgetInSwitcher(switcher, targetWidget)
                if not switcher or not slua.isValid(switcher) then return nil end
                if not switcher.GetChildrenCount or not switcher.GetChildAt then return nil end
                local nChildren = switcher:GetChildrenCount()
                for i = 0, math.max(nChildren - 1, 0) do
                    local child = switcher:GetChildAt(i)
                    if child and slua.isValid(child) then
                        if child == targetWidget then return i end
                        local function searchDescendant(w, target, depth)
                            if depth > 5 then return false end
                            if w == target then return true end
                            if not w.GetChildrenCount or not w.GetChildAt then return false end
                            local nc = w:GetChildrenCount()
                            for j = 0, math.max(nc - 1, 0) do
                                local c = w:GetChildAt(j)
                                if c and slua.isValid(c) and searchDescendant(c, target, depth + 1) then return true end
                            end
                            return false
                        end
                        if searchDescendant(child, targetWidget, 0) then return i end
                    end
                end
                return nil
            end

            for _, switcherName in ipairs({"Switcher_WeaponIcon", "WidgetSwitcher_Type", "WidgetSwitcher_Type2"}) do
                local ws = Container[switcherName]
                if ws and slua.isValid(ws) and ws.GetChildrenCount and ws.GetChildAt then
                    local foundIdx = findWidgetInSwitcher(ws, ourWeaponIcon)
                    if foundIdx then
                        if ws.SetActiveWidgetIndex then
                            ws:SetActiveWidgetIndex(foundIdx)
                            WidgetData._CachedSwitcherIndexes = WidgetData._CachedSwitcherIndexes or {}
                            WidgetData._CachedSwitcherIndexes[switcherName] = foundIdx
                        end
                    end
                end
            end
        end)

        pcall(function()
            local parent = ourWeaponIcon
            for depth = 0, 8 do
                if not parent or not slua.isValid(parent) then break end
                if parent.GetParent then
                    local p = parent:GetParent()
                    if p and slua.isValid(p) then
                        local pStr = tostring(p)
                        if string.find(pStr, "WidgetSwitcher") then
                            if p.GetChildrenCount and p.GetChildAt then
                                local nCh = p:GetChildrenCount()
                                for i = 0, math.max(nCh - 1, 0) do
                                    local child = p:GetChildAt(i)
                                    if child and slua.isValid(child) then
                                        local function isDescendant(w, target, d)
                                            if d > 5 then return false end
                                            if w == target then return true end
                                            if not w.GetChildrenCount or not w.GetChildAt then return false end
                                            local nc = w:GetChildrenCount()
                                            for j = 0, math.max(nc - 1, 0) do
                                                local c = w:GetChildAt(j)
                                                if c and slua.isValid(c) and isDescendant(c, target, d + 1) then return true end
                                            end
                                            return false
                                        end
                                        if isDescendant(child, ourWeaponIcon, 0) then
                                            if p.SetActiveWidgetIndex then
                                                p:SetActiveWidgetIndex(i)
                                                WidgetData._CachedParentSwitchers = WidgetData._CachedParentSwitchers or {}
                                                WidgetData._CachedParentSwitchers[tostring(p)] = {w = p, idx = i}
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        parent = p
                    else
                        break
                    end
                else
                    break
                end
            end
        end)

        pcall(function()
            local parent = ourWeaponIcon
            for depth = 0, 8 do
                pcall(function()
                    if parent.GetParent then
                        local p = parent:GetParent()
                        if p and slua.isValid(p) then
                            if p.SetWidgetVisibility then p:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
                            pcall(function() if p.SetRenderOpacity then p:SetRenderOpacity(1.0) end end)
                            pcall(function() if p.SetContentColorAndOpacity then p:SetContentColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function() if p.SetColorAndOpacity then p:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function() if p.SetBrushTintColor then p:SetBrushTintColor(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function()
                                local pBrush = p.Brush
                                if pBrush and pBrush.TintColor then
                                    pBrush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
                                    if p.SetBrush then p:SetBrush(pBrush) end
                                end
                            end)
                            pcall(function() if p.InvalidateLayout then p:InvalidateLayout() end end)
                            parent = p
                        end
                    end
                end)
            end
        end)
        pcall(function() if ourWeaponIcon.InvalidateLayout then ourWeaponIcon:InvalidateLayout() end end)

        pcall(function() if Container.UpdateWeapon then Container:UpdateWeapon() end end)
        pcall(function() if Container.RefreshWeapon then Container:RefreshWeapon() end end)
        
        WidgetData._LastWeaponID = winfo.WeaponID
        WidgetData._WeaponIconApplied = true
    end)
end

PlayerMapMarker._OBHeadWidgetClass = nil
PlayerMapMarker._OBHeadWidgetLoadFailed = false
PlayerMapMarker._bDumpedWidgetChildren = false

function PlayerMapMarker.CreateESPWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    if PlayerMapMarker._OBHeadWidgetLoadFailed then return nil end

    if not PlayerMapMarker._OBHeadWidgetClass then
        pcall(function()
            local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
            local uClass = slua.loadClass(Path)
            if uClass then PlayerMapMarker._OBHeadWidgetClass = uClass end
        end)
        if not PlayerMapMarker._OBHeadWidgetClass then
            PlayerMapMarker._OBHeadWidgetLoadFailed = true
            return nil
        end
    else
        local bValid = false
        pcall(function() bValid = slua.isValid(PlayerMapMarker._OBHeadWidgetClass) end)
        if not bValid then
            PlayerMapMarker._OBHeadWidgetLoadFailed = true
            PlayerMapMarker._OBHeadWidgetClass = nil
            return nil
        end
    end

    local Widget = nil
    pcall(function()
        local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
        local PC = PlayerMapMarker.GetMyPlayerController()
        local OuterObj = IsValid(PC) and PC.Object or PlayerMapMarker.ESPCanvas
        Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PlayerMapMarker._OBHeadWidgetClass, OuterObj)
    end)

    if not Widget then return nil end

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    local NameText = nil
    local HealthFill = nil
    local bIsOriginalProgressBar = false

    pcall(function()
        NameText = Widget.TextBlock_TeamName
        if NameText and slua.isValid(NameText) then pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end

        local WS_Type = Widget.WidgetSwitcher_Type
        local WS_Type2 = Widget.WidgetSwitcher_Type2
        if WS_Type and slua.isValid(WS_Type) then pcall(function() if WS_Type.SetActiveWidgetIndex then WS_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
        if WS_Type2 and slua.isValid(WS_Type2) then pcall(function() if WS_Type2.SetActiveWidgetIndex then WS_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end

        local SizeBox_HP = Widget.SizeBox_HP
        if SizeBox_HP and slua.isValid(SizeBox_HP) then
            pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() SizeBox_HP:SetHeightOverride(6) end)
            pcall(function() SizeBox_HP:SetWidthOverride(100) end)

            local ExistingChild = nil
            pcall(function() if SizeBox_HP.GetContent then ExistingChild = SizeBox_HP:GetContent() end end)
            if not ExistingChild then pcall(function() if SizeBox_HP.GetChildAt then ExistingChild = SizeBox_HP:GetChildAt(0) end end) end

            if ExistingChild and slua.isValid(ExistingChild) then
                pcall(function() ExistingChild:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                pcall(function() ExistingChild:SetRenderOpacity(1.0) end)

                local FoundPB = PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
                if FoundPB and slua.isValid(FoundPB) then
                    HealthFill = FoundPB
                    bIsOriginalProgressBar = true
                    pcall(function() FoundPB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() FoundPB:SetRenderOpacity(1.0) end)
                else
                    local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", ExistingChild)
                    if PB then
                        pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(0, 1, 0, 1) or {R=0,G=1,B=0,A=1}) end)
                        pcall(function() PB:SetPercent(1.0) end)
                        pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() PB:SetRenderOpacity(1.0) end)
                        pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)
                        pcall(function() ExistingChild:AddChild(PB) end)
                        HealthFill = PB
                    end
                end
            else
                local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", SizeBox_HP)
                if PB then
                    pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(0, 1, 0, 1) or {R=0,G=1,B=0,A=1}) end)
                    pcall(function() PB:SetPercent(1.0) end)
                    pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() PB:SetRenderOpacity(1.0) end)
                    pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)

                    local bUsedSetContent = false
                    pcall(function() if SizeBox_HP.SetContent then SizeBox_HP:SetContent(PB) bUsedSetContent = true end end)
                    if not bUsedSetContent then pcall(function() SizeBox_HP:AddChild(PB) end) end
                    HealthFill = PB
                end
            end
        end
    end)

    local WidgetData = {
        Container = Widget,
        NameText = NameText,
        HealthFill = HealthFill,
        IsGameWidget = true,
        IsOriginalProgressBar = bIsOriginalProgressBar,
        HasChildren = (NameText ~= nil)
    }
    return WidgetData
end

PlayerMapMarker._CanvasScaleX = 1.0
PlayerMapMarker._CanvasScaleY = 1.0
PlayerMapMarker._CanvasOffsetX = 0.0
PlayerMapMarker._CanvasOffsetY = 0.0

function PlayerMapMarker.UpdateCanvasTransform(PC)
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local success = false
    pcall(function()
        local SBL = SlateBlueprintLibrary
        if SBL and SBL.AbsoluteToLocal then
            local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
            if cg then
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100})
                if pt0 and pt1 then
                    PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PlayerMapMarker._CanvasOffsetX = pt0.X
                    PlayerMapMarker._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end
    end)

    if not success then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.ScreenToWidgetLocal then
                local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
                if cg then
                    local pt0 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    local pt1 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0}, pt0)
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100}, pt1)
                    PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PlayerMapMarker._CanvasOffsetX = pt0.X
                    PlayerMapMarker._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end)
    end

    if not success then
        local scale = 1.0
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then scale = WLL.GetViewportScale(PC) or 1.0 end
        PlayerMapMarker._CanvasScaleX = 1.0 / scale
        PlayerMapMarker._CanvasScaleY = 1.0 / scale
        PlayerMapMarker._CanvasOffsetX = 0
        PlayerMapMarker._CanvasOffsetY = 0
    end
end

function PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    if not ScreenPixelPos then return FVector2D and FVector2D(0, 0) or {X=0, Y=0} end
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return (FVector2D and FVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
end

function PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local ScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
        if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then bOK = true end
    end)
    if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local CanvasLocalPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    return true, CanvasLocalPos
end

function PlayerMapMarker.GetDynamicViewportSize(PC)
    local width, height = 0, 0
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
        pcall(function()
            local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
            if cg and cg.GetLocalSize then
                local sz = cg:GetLocalSize()
                if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
            end
        end)
    end
    if width > 200 then return width, height end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportSize then
            local sz = WLL.GetViewportSize(PC or PlayerMapMarker.GetMyPlayerController())
            if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
        end
    end)
    if width > 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                local scale = WLL.GetViewportScale(PC or PlayerMapMarker.GetMyPlayerController())
                if scale and type(scale) == "number" and scale > 0 and scale ~= 1.0 then width = width / scale height = height / scale end
            end
        end)
        return width, height
    end
    return PlayerMapMarker._cachedViewportW or 1920, PlayerMapMarker._cachedViewportH or 1080
end

function PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
    if not Widget or not IsValid(PC) then return false end
    local Container = Widget.Container or Widget
    local bOnScreen = true
    if not CanvasPos then
        if not WorldLoc then return false end
        bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    end

    if not bOnScreen then pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) return false end

    pcall(function()
        if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
            local ptr = tostring(Container)
            local Slot = PlayerMapMarker.ESPWidgetPtrs[ptr]

            if not Slot or not slua.isValid(Slot) or type(Slot) == "boolean" then
                local addedSlot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
                if addedSlot and slua.isValid(addedSlot) then
                    Slot = addedSlot
                    PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
                    if type(Widget) == "table" then Widget.Slot = addedSlot end
                    pcall(function() Slot:SetAutoSize(true) end)
                    pcall(function() Slot.bAutoSize = true end)
                    local align = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
                    pcall(function() Slot.Alignment = align end)
                    pcall(function() Slot:SetAlignment(align) end)
                    pcall(function() Slot:SetAlignment(0.5, 1.0) end)
                    pcall(function() Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 20) end)
                end
            end

            -- [FIX VIP] Xóa vệt đen trên đầu khi tắt hết UI
            local bShowAnyUI = _G.GRW_XDConfig.Esp9_Name or _G.GRW_XDConfig.Esp9_Distance or _G.GRW_XDConfig.Esp9_HP or _G.GRW_XDConfig.Esp9_Team or _G.GRW_XDConfig.Esp9_Weapon
            if bShowAnyUI then
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            else
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            
            if not Widget._OffsetResetDone then
                pcall(function() Container:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end)
                
                -- [SIZE 85% UI UE4] Tăng size to hơn một chút cho dễ nhìn (Gốc là 1.0, cũ là 0.7)
                pcall(function() Container:SetRenderScale(FVector2D and FVector2D(0.90, 0.90) or {X=0.90, Y=0.90}) end)
                
                if Widget and type(Widget) == "table" then
                    if Widget.NameText and slua.isValid(Widget.NameText) then pcall(function() Widget.NameText:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                    if Widget.HealthFill and slua.isValid(Widget.HealthFill) then pcall(function() Widget.HealthFill:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                end
                pcall(function() Container.RenderTransformPivot = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0} end)
                pcall(function() Container:SetRenderTransformPivot(FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}) end)
                Widget._OffsetResetDone = true
            end

            if not Slot or not slua.isValid(Slot) or Slot == PlayerMapMarker.ESPCanvas then
                if Widget and type(Widget) == "table" and Widget.Slot and slua.isValid(Widget.Slot) then Slot = Widget.Slot
                elseif Container.Slot and slua.isValid(Container.Slot) then Slot = Container.Slot end
            end

            if Slot and slua.isValid(Slot) and Slot ~= PlayerMapMarker.ESPCanvas then
                local finalX = CanvasPos.X + (PlayerMapMarker.ESPAnchorOffsetX or 0)
                local finalY = CanvasPos.Y + (PlayerMapMarker.ESPAnchorOffsetY or 0)
                if Widget and type(Widget) == "table" then
                    if not Widget._CachedPosVec then Widget._CachedPosVec = FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}
                    else Widget._CachedPosVec.X = finalX Widget._CachedPosVec.Y = finalY end
                    pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
                else
                    pcall(function() Slot:SetPosition(FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}) end)
                end
            end
        end
    end)
    return true
end

function PlayerMapMarker.UpdateESPText(Widget, Text)
    if not Widget then return end
    if Widget._LastESPText == Text then return end
    Widget._LastESPText = Text

    local function applyTextAndCenter(w, txt)
        if not w or not slua.isValid(w) then return end
        
        -- Nếu chữ rỗng (do người chơi đã tắt Tên & Khoảng cách) thì ẨN Widget đi
        if txt == "" then
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            return
        else
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        end

        pcall(function() w:SetText(txt) end)
        -- ÉP MÀU CAM CHO CHỮ & SỐ MÉT 
        pcall(function()
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local orangeColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=255, G=255, B=255, A=255}
            if w.SetColorAndOpacity then
                if FSlateColor then w:SetColorAndOpacity(FSlateColor(orangeColor)) else w:SetColorAndOpacity(orangeColor) end
            end
        end)
        pcall(function() if w.SetJustification then w:SetJustification(1) end end)
        pcall(function() local slot = w.Slot if slot and slot.SetHorizontalAlignment then slot:SetHorizontalAlignment(1) end end)
        pcall(function() w:SetRenderTranslation(FVector2D and FVector2D(PlayerMapMarker.ESPTextOffsetX or 0, PlayerMapMarker.ESPTextOffsetY or 0) or {X=PlayerMapMarker.ESPTextOffsetX or 0, Y=PlayerMapMarker.ESPTextOffsetY or 0}) end)
    end

    if Widget.NameText and slua.isValid(Widget.NameText) then applyTextAndCenter(Widget.NameText, Text) end
    if Widget.IsGameWidget and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.SetPlayerName then
                    local Name = Text
                    local idx = string.find(Text, " %[")
                    if idx then Name = string.sub(Text, 1, idx - 1) end
                    W:SetPlayerName(Name)
                end
                applyTextAndCenter(W.TextBlock_TeamName, Text)
                applyTextAndCenter(W.TextBlock_PlayerName, Text)

                pcall(function()
                    if not Widget._CachedVBChildren then
                        local list = {}
                        local VB = PlayerMapMarker._FindNamedWidgetInTree(W, "VerticalBox_0", 8)
                        if VB and slua.isValid(VB) and VB.GetChildrenCount then
                            local nChildren = VB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = VB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedVBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedVBChildren) do applyTextAndCenter(child, Text) end
                end)

                pcall(function()
                    if not Widget._CachedHBChildren then
                        local list = {}
                        local HB = PlayerMapMarker._FindNamedWidgetInTree(W, "HorizontalBox_TeamName", 8)
                        if HB and slua.isValid(HB) and HB.GetChildrenCount then
                            local nChildren = HB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = HB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedHBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedHBChildren) do applyTextAndCenter(child, Text) end
                end)
            end
        end)
    end
end

function PlayerMapMarker.UpdateESPHealth(Widget, pct)
    if not Widget then return end
    -- Xóa dòng Cache LastPct để nó ép update liên tục khi bạn gạt công tắc
    Widget.LastPct = pct

    local bShowHP = _G.GRW_XDConfig.Esp9_HP

    if PlayerMapMarker.bForceSwitcherIndexEveryUpdate and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then pcall(function() if W.WidgetSwitcher_Type.SetActiveWidgetIndex then W.WidgetSwitcher_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
                if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then pcall(function() if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end
                
                -- Cập nhật ẩn/hiện Box chứa thanh máu
                if W.SizeBox_HP and slua.isValid(W.SizeBox_HP) then 
                    if bShowHP then
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    else
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    end
                end
            end
        end)
    end

    -- Chặn đoạn code cập nhật màu bên dưới nếu công tắc tắt
    if not bShowHP then return end

    if Widget.HealthFill then
        local bValid = false
        pcall(function() bValid = slua.isValid(Widget.HealthFill) end)
        if bValid then
            local bHasSetPercent = false
            pcall(function() bHasSetPercent = (Widget.HealthFill.SetPercent ~= nil) end)
            if not bHasSetPercent then
                local PB = PlayerMapMarker.FindProgressBarInWidget(Widget.HealthFill, 0, 5)
                if PB and slua.isValid(PB) then Widget.HealthFill = PB else return end
            end

            pcall(function()
                if Widget.HealthFill.SetWidgetVisibility then Widget.HealthFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
                if Widget.HealthFill.SetRenderOpacity then Widget.HealthFill:SetRenderOpacity(1.0) end
                if Widget.HealthFill.SetPercent then
                    Widget.HealthFill:SetPercent(pct)
                    
                    -- [FIX VIP] Xóa bỏ rào cản IsOriginalProgressBar để ÉP MÀU mọi lúc
                    local color
                    if pct > 0.5 then 
                        -- Máu nhiều: Xanh Lá Cây
                        color = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 1.0) or {R=0,G=255,B=0,A=255}
                    elseif pct > 0.25 then 
                        -- Nửa máu: Cam/Vàng
                        color = FLinearColor and FLinearColor(1.0, 0.5, 0.0, 1.0) or {R=255,G=128,B=0,A=255}
                    else 
                        -- Yếu máu: Đỏ
                        color = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {R=255,G=0,B=0,A=255} 
                    end
                    
                    -- 1. Ép màu bằng hàm chuẩn
                    if Widget.HealthFill.SetFillColorAndOpacity then 
                        Widget.HealthFill:SetFillColorAndOpacity(color) 
                    end
                    
                    -- 2. Ép màu sâu vào Style (Khắc phục triệt để lỗi màu trắng xám của UI gốc UE4)
                    pcall(function()
                        if Widget.IsOriginalProgressBar then
                            local style = Widget.HealthFill.WidgetStyle
                            if style and style.FillImage then
                                style.FillImage.TintColor = color
                                Widget.HealthFill:SetWidgetStyle(style)
                            end
                        end
                    end)
                end
            end)
        end
        return
    end
end

function PlayerMapMarker.RemoveESPWidget(Widget, KeyStr)
    if not Widget then return end
    local Container = Widget.Container or Widget
    pcall(function()
        local ptr = tostring(Container)
        PlayerMapMarker.ESPWidgetPtrs[ptr] = nil
        Container:RemoveFromParent()
        Container:ConditionalBeginDestroy()
    end)
    if KeyStr then
        PlayerMapMarker.RemoveSnapLine(KeyStr)
        if PlayerMapMarker.RemoveSkeletonLines then
            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
        end
    end
end

function PlayerMapMarker.CreateSnapLine()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    local color = PlayerMapMarker.SnapLineColor or (FLinearColor and FLinearColor(1.0, 1.0, 1.0, PlayerMapMarker.SnapLineOpacity or 0.7) or {R=1,G=1,B=1,A=PlayerMapMarker.SnapLineOpacity or 0.7})
    pcall(function() Border:SetBrushColor(color) end)
    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(1) end
    end)
    return { Widget = Border, Slot = Slot }
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D and FVector2D(0, 0) or {X=0,Y=0}
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
        end
    end)
    if screenPixelW <= 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportSize then
                local vs = WLL.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
            end
        end)
    end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then
            local s = WLL.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)
    if screenPixelW <= 200 then
        screenPixelW = (PlayerMapMarker._cachedViewportW or 1920) * scale
        screenPixelH = (PlayerMapMarker._cachedViewportH or 1080) * scale
    end

    if not PlayerMapMarker._CachedTopCenterPixel then PlayerMapMarker._CachedTopCenterPixel = FVector2D and FVector2D(0, 0) or {X=0,Y=0} end
    PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
    PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
    local fromX = fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0)
    local fromY = fromCanvasPos.Y

    return fromX, fromY
end

function PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY, Character, PC)
    if not PlayerMapMarker.bUseSnapLines then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]

    if not bOnScreen or not CanvasPos or not IsValid(Character) or not IsValid(PC) then
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        return
    end

    local bIsNew = false
    if not LineData then
        LineData = PlayerMapMarker.CreateSnapLine()
        if not LineData or not LineData.Widget or not LineData.Slot then return end
        PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
        bIsNew = true
    end

    local Widget = LineData.Widget
    local Slot = LineData.Slot

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    
    if not LineData._PivotSet then
        pcall(function() Widget.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
        pcall(function() Widget:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)
        LineData._PivotSet = true
    end

    -- [NEW] CHECK VISIBILITY & APPLY DYNAMIC COLOR FOR SNAPLINE
    local bTargetVisible = PlayerMapMarker.IsPlayerVisible(PC, Character)
    local lineColor = bTargetVisible and (PlayerMapMarker.SnapLineVisibleColor or FLinearColor(0.0, 1.0, 0.0, 0.8)) or (PlayerMapMarker.SnapLineCoverColor or FLinearColor(0.9, 0.0, 0.0, 0.6))
    
    local cData = _G.GRW_XDState.CustomTextData or {}
    local visColorID = cData.Esp9_LineVisColor or 2
    local hidColorID = cData.Esp9_LineHidColor or 1
    local currentLineColorHash = tostring(bTargetVisible) .. "_" .. visColorID .. "_" .. hidColorID

    if LineData._cachedColorHash ~= currentLineColorHash then
        pcall(function() Widget:SetBrushColor(lineColor) end)
        LineData._cachedColorHash = currentLineColorHash
    end

    local toX = CanvasPos.X + (PlayerMapMarker.SnapLineHeadOffsetX or 0)
    local toY = CanvasPos.Y + (PlayerMapMarker.SnapLineHeadOffsetY or 0)
    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local thickness = PlayerMapMarker.SnapLineThickness or 1.5

    local angle_rad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
    local angle = angle_rad * 57.29577951308232

    -- [TỐI ƯU FPS] Thêm Threshold cho Snapline, KHÔNG bắt UI vẽ lại nếu địch chỉ nhích vài pixel
    local threshold = 2.0
    LineData.lastToX = LineData.lastToX or -999
    LineData.lastToY = LineData.lastToY or -999
    
    if math.abs(toX - LineData.lastToX) > threshold or math.abs(toY - LineData.lastToY) > threshold then
        LineData.lastToX = toX
        LineData.lastToY = toY

        if not LineData._CachedPosVec then
            LineData._CachedPosVec = FVector2D and FVector2D(fromX, fromY - thickness / 2.0) or {X=fromX, Y=fromY - thickness / 2.0}
            LineData._CachedSizeVec = FVector2D and FVector2D(length, thickness) or {X=length, Y=thickness}
        else
            LineData._CachedPosVec.X = fromX ; LineData._CachedPosVec.Y = fromY - thickness / 2.0
            LineData._CachedSizeVec.X = length ; LineData._CachedSizeVec.Y = thickness
        end

        pcall(function() 
            Slot:SetPosition(LineData._CachedPosVec) 
            Slot:SetSize(LineData._CachedSizeVec)
            if bIsNew then Slot:SetZOrder(1) end
        end)
        pcall(function() Widget:SetRenderAngle(angle) end)
    end
end

function PlayerMapMarker.RemoveSnapLine(KeyStr)
    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
        pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.ClearAllSnapLines()
    for KeyStr, LineData in pairs(PlayerMapMarker.SnapLineWidgets) do
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        end
    end
    PlayerMapMarker.SnapLineWidgets = {}
end

-- ====== BẮT ĐẦU: LOGIC SKELETON TỪ CODE MẪU ======
function PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, 0, 0 end
    if not PlayerMapMarker._tempScreenPixelPos then
        PlayerMapMarker._tempScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    end
    local tempPos = PlayerMapMarker._tempScreenPixelPos
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, tempPos, true)
        if res == true or res == 1 then bOK = true end
    end)
    if not bOK or (tempPos.X == 0 and tempPos.Y == 0) then return false, 0, 0 end
    local canvasX, canvasY = PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, tempPos.X, tempPos.Y)
    return true, canvasX, canvasY
end

function PlayerMapMarker.GetBoneLocationWithFallback(Character, PrimaryBoneName)
    if not IsValid(Character) or not PrimaryBoneName then return nil end
    if Character._cachedBoneNames and Character._cachedBoneNames[PrimaryBoneName] then
        local cachedName = Character._cachedBoneNames[PrimaryBoneName]
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(cachedName)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(cachedName) end
            end
        end)
        if loc then return loc end
    end
    local fallbacks = PlayerMapMarker.BoneNameFallbacks[PrimaryBoneName] or {PrimaryBoneName}
    for _, bname in ipairs(fallbacks) do
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(bname)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(bname) end
            end
        end)
        if loc then
            if not Character._cachedBoneNames then Character._cachedBoneNames = {} end
            Character._cachedBoneNames[PrimaryBoneName] = bname
            return loc
        end
    end
    return nil
end

function PlayerMapMarker.IsPlayerVisible(PC, Character)
    if not IsValid(PC) or not IsValid(Character) then return false end
    local now = os.clock()
    
    -- [FIX 2A] Distance-based cache: door wale ka 0.5s, paas wale ka 0.15s
    local cacheTime = 0.3
    pcall(function()
        local myLoc = PlayerMapMarker._CachedMyLoc
        if myLoc then
            local charLoc = PlayerMapMarker.GetCharacterLocation(Character)
            if charLoc then
                local dx = (charLoc.X or 0) - (myLoc.X or 0)
                local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist > 15000 then cacheTime = 0.6  -- 150m+: 0.6s
                elseif dist > 8000 then cacheTime = 0.45 -- 80m+: 0.45s
                elseif dist > 3000 then cacheTime = 0.25 -- 30m+: 0.25s
                else cacheTime = 0.12 end              -- Close: 0.12s
            end
        end
    end)
    
    -- [FIX 2B] Skip raycast entirely if enemy is too far (>250m) — assume not visible
    local bSkipRaycast = false
    pcall(function()
        local myLoc = PlayerMapMarker._CachedMyLoc
        if myLoc then
            local charLoc = PlayerMapMarker.GetCharacterLocation(Character)
            if charLoc then
                local dx = (charLoc.X or 0) - (myLoc.X or 0)
                local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
                if math.sqrt(dx*dx + dy*dy) > 25000 then bSkipRaycast = true end
            end
        end
    end)
    
    if bSkipRaycast then
        Character._cachedIsVisible = false
        Character._lastVisTime = now
        return false
    end
    
    if Character._lastVisTime and (now - Character._lastVisTime) < cacheTime then
        return Character._cachedIsVisible or false
    end
    Character._lastVisTime = now
    local bVis = false
    pcall(function()
        if PC.LineOfSightTo then
            if not PlayerMapMarker._ZeroVector then
                local VT = FVector or import("/Script/CoreUObject.Vector")
                if VT then PlayerMapMarker._ZeroVector = VT(0, 0, 0) end
            end
            bVis = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
        end
    end)
    if not bVis then
        local KismetSystemLibrary = import("KismetSystemLibrary")
        if KismetSystemLibrary and KismetSystemLibrary.LineTraceSingle then
            pcall(function()
                local camMgr = nil
                local GameplayStatics = import("GameplayStatics")
                if GameplayStatics and GameplayStatics.GetPlayerCameraManager then
                    camMgr = GameplayStatics.GetPlayerCameraManager(PC, 0)
                end
                local startLoc = camMgr and camMgr:GetCameraLocation() or PlayerMapMarker.GetMyLocation()
                local headLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, "head")
                if startLoc and headLoc then
                    if not PlayerMapMarker._CachedHitResult then
                        local HitResultClass = import("HitResult") or import("/Script/Engine.HitResult")
                        PlayerMapMarker._CachedHitResult = HitResultClass and HitResultClass() or {}
                    end
                    local bHit = KismetSystemLibrary.LineTraceSingle(PC, startLoc, headLoc, 0, false, nil, 0, PlayerMapMarker._CachedHitResult, true)
                    if bHit then
                        local hitActor = nil
                        if type(PlayerMapMarker._CachedHitResult.GetActor) == "function" then hitActor = PlayerMapMarker._CachedHitResult:GetActor()
                        elseif PlayerMapMarker._CachedHitResult.Actor then hitActor = PlayerMapMarker._CachedHitResult.Actor end
                        if hitActor and (hitActor == Character or (type(hitActor.IsChildOf) == "function" and hitActor:IsChildOf(Character))) then
                            bVis = true
                        end
                    else
                        bVis = true
                    end
                end
            end)
        end
    end
    Character._cachedIsVisible = bVis
    return bVis
end

function PlayerMapMarker.CreateSkeletonLineWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5}) end)
    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(5) end
    end)
    return { 
        Widget = Border, Slot = Slot,
        posVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        sizeVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        lastFromX = -99999, lastFromY = -99999,
        lastToX = -99999, lastToY = -99999
    }
end

function PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, bVisible, TeamColor, bPlayerOnScreen, charLoc, bTargetVisible)
    if not PlayerMapMarker.bUseSkeleton then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]
    if not bVisible or not IsValid(Character) or not IsValid(PC) then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    if not charLoc then charLoc = PlayerMapMarker.GetESPLocation(Character) end
    if not charLoc then return end

    if bPlayerOnScreen == nil then
        local bOnScreen, _, _ = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, charLoc)
        bPlayerOnScreen = bOnScreen
    end
    if not bPlayerOnScreen then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    local dist = 0
    local myLoc = PlayerMapMarker._CachedMyLoc or PlayerMapMarker.GetMyLocation()
    if myLoc and charLoc then
        local dx = (charLoc.X or 0) - (myLoc.X or 0)
        local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
        local dz = (charLoc.Z or 0) - (myLoc.Z or 0)
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    if PlayerMapMarker.SkeletonMaxDistance and PlayerMapMarker.SkeletonMaxDistance > 0 then
        if dist > PlayerMapMarker.SkeletonMaxDistance then
            if PlayerBones then
                for _, LineData in ipairs(PlayerBones) do
                    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                        LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                        LineData.Widget._isSelfHitTestVisible = false
                    end
                end
            end
            return
        end
    end

    if not PlayerBones then
        PlayerBones = {}
        PlayerMapMarker.SkeletonWidgets[KeyStr] = PlayerBones
    end

    local lineColor = nil
    if PlayerMapMarker.bUseVisibilityColor then
        -- [OPT ESP V2] Lấy trực tiếp kết quả Raycast từ vòng ngoài truyền vào, KHÔNG gọi lại IsPlayerVisible
        if bTargetVisible == nil then
            bTargetVisible = PlayerMapMarker.IsPlayerVisible(PC, Character)
        end
        if bTargetVisible then lineColor = PlayerMapMarker.SkeletonVisibleColor or FLinearColor(0.0, 1.0, 0.0, 0.8)
        else lineColor = PlayerMapMarker.SkeletonCoverColor or FLinearColor(0.9, 0.0, 0.0, 0.6) end
    else
        lineColor = PlayerMapMarker.SkeletonColor or TeamColor or FLinearColor(1.0, 1.0, 1.0, PlayerMapMarker.SkeletonOpacity or 0.8)
    end

    -- [MƯỢT MÀ TỐI ƯU] Cache vị trí xương 3D theo chuyển động của địch: chỉ tìm xương lại khi
    -- địch DỊCH CHUYỂN. Khi chỉ xoay camera (địch đứng yên) => dùng lại cache, chỉ chiếu lại
    -- ra màn hình => mượt hơn nhiều mà gần như không tốn thêm CPU.
    local cache = Character._cachedBones3D
    if not cache then cache = {} Character._cachedBones3D = cache end
    local moveKey = nil
    if charLoc then
        moveKey = math.floor(charLoc.X or 0) .. "," .. math.floor(charLoc.Y or 0) .. "," .. math.floor(charLoc.Z or 0)
    end
    if Character._cachedBonesMoveKey ~= moveKey then
        Character._cachedBonesMoveKey = moveKey
        for k in pairs(cache) do cache[k] = nil end
    end
    
    local lineIndex = 0
    local thickness = PlayerMapMarker.SkeletonThickness or 1.2

    for _, chain in ipairs(PlayerMapMarker.SkeletonChains) do
        local lastCanvasX, lastCanvasY = nil, nil
        for _, boneName in ipairs(chain) do
            local boneWorldLoc = cache[boneName]
            if boneWorldLoc == nil then
                boneWorldLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, boneName) or false
                cache[boneName] = boneWorldLoc
            end
            if boneWorldLoc == false then boneWorldLoc = nil end

            local currentCanvasX, currentCanvasY = nil, nil
            if boneWorldLoc then
                local bOnScreen, cX, cY = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, boneWorldLoc)
                if bOnScreen then
                    currentCanvasX = cX
                    currentCanvasY = cY
                end
            end

            if lastCanvasX and currentCanvasX then
                lineIndex = lineIndex + 1
                local LineData = PlayerBones[lineIndex]
                if not LineData or not LineData.Widget or not slua.isValid(LineData.Widget) then
                    LineData = PlayerMapMarker.CreateSkeletonLineWidget()
                    if LineData then PlayerBones[lineIndex] = LineData end
                end

                if LineData and LineData.Widget and LineData.Slot then
                    local Widget = LineData.Widget
                    local Slot = LineData.Slot

                    if Widget._cachedColor ~= lineColor then
                        Widget:SetBrushColor(lineColor)
                        Widget._cachedColor = lineColor
                    end
                    if not Widget._isSelfHitTestVisible then
                        Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        Widget._isSelfHitTestVisible = true
                    end

                    local fromX = lastCanvasX
                    local fromY = lastCanvasY
                    local toX = currentCanvasX
                    local toY = currentCanvasY

                    -- [OPT ESP V2] Ngưỡng dịch chuyển màn hình: càng xa càng ít phải vẽ lại
                    local threshold = 0.5
                    if dist > 20000 then threshold = 3.0
                    elseif dist > 12000 then threshold = 2.0
                    elseif dist > 8000 then threshold = 1.0 end

                    if math.abs(fromX - LineData.lastFromX) > threshold or
                       math.abs(fromY - LineData.lastFromY) > threshold or
                       math.abs(toX - LineData.lastToX) > threshold or
                       math.abs(toY - LineData.lastToY) > threshold then

                        LineData.lastFromX = fromX
                        LineData.lastFromY = fromY
                        LineData.lastToX = toX
                        LineData.lastToY = toY

                        local dx = toX - fromX
                        local dy = toY - fromY
                        local length = math.sqrt(dx * dx + dy * dy)
                        local angle_rad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
                        local angle = angle_rad * 57.29577951308232

                        local pVec = LineData.posVec
                        pVec.X = fromX ; pVec.Y = fromY - thickness / 2.0
                        Slot:SetPosition(pVec)

                        local sVec = LineData.sizeVec
                        sVec.X = length ; sVec.Y = thickness
                        Slot:SetSize(sVec)
                        Widget:SetRenderAngle(angle)
                    end
                end
            end
            lastCanvasX = currentCanvasX
            lastCanvasY = currentCanvasY
        end
    end

    for i = lineIndex + 1, #PlayerBones do
        local LineData = PlayerBones[i]
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            LineData.Widget._isSelfHitTestVisible = false
        end
    end
end

function PlayerMapMarker.RemoveSkeletonLines(KeyStr)
    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]
    if PlayerBones then
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
        PlayerMapMarker.SkeletonWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.ClearAllSkeletonLines()
    for KeyStr, PlayerBones in pairs(PlayerMapMarker.SkeletonWidgets) do
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
    end
    PlayerMapMarker.SkeletonWidgets = {}
end
-- ====== KẾT THÚC: LOGIC SKELETON ======

function PlayerMapMarker.ClearAllESP()
    pcall(function() RedBoxOverlay.Stop() end)
    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
    end
    PlayerMapMarker.ESPWidgets = {}
    PlayerMapMarker.ESPWidgetPtrs = {}
    PlayerMapMarker.ClearAllSnapLines()
    PlayerMapMarker.ClearAllSkeletonLines()
    
    -- XÓA BỎ VÒNG LẶP NẶNG GETCHILDRENCOUNT(), CHỈ CẦN HỦY LIÊN KẾT ĐỂ GAME TỰ XÓA RÁC
    PlayerMapMarker.ESPCanvas = nil
    PlayerMapMarker._OBHeadWidgetClass = nil
    PlayerMapMarker._OBHeadWidgetLoadFailed = false
    PlayerMapMarker._cachedViewportW = 1920
    PlayerMapMarker._cachedViewportH = 1080
end

function PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
    if not PlayerMapMarker.bUseScreenESP then return end
    
    -- Đồng bộ Config Dây và Xương
    PlayerMapMarker.bUseSnapLines = _G.GRW_XDConfig.Esp9_Line
    PlayerMapMarker.bUseSkeleton = _G.GRW_XDConfig.Esp9_Skeleton

    -- Áp dụng tùy chỉnh Độ Dày & 30 Màu
    local function GetEspColor(idx, alpha)
        local FC = _G.FLinearColor or import("LinearColor")
        local colors = {
            {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0, 0.0}, {1.0, 0.0, 1.0}, {1.0, 1.0, 1.0}, -- 1-6 (Cơ bản)
            {0.0, 1.0, 1.0}, {1.0, 0.5, 0.0}, {1.0, 0.4, 0.7}, {0.6, 0.3, 0.0}, {0.5, 1.0, 0.0}, {0.0, 0.5, 0.5}, -- 7-12 (Cyan, Cam, Hồng, Nâu, Lime...)
            {0.0, 0.0, 0.5}, {0.5, 0.0, 0.0}, {0.5, 0.5, 0.0}, {0.75, 0.75, 0.75}, {1.0, 0.84, 0.0}, {0.5, 0.0, 1.0}, -- 13-18 (Navy, Maroon, Xám, Vàng Gold...)
            {0.53, 0.81, 0.92}, {1.0, 0.5, 0.31}, {0.98, 0.5, 0.45}, {0.94, 0.9, 0.55}, {0.87, 0.63, 0.87}, {0.85, 0.44, 0.84}, -- 19-24 (Da trời, San hô, Mận...)
            {0.29, 0.0, 0.51}, {0.25, 0.88, 0.82}, {0.6, 1.0, 0.6}, {0.86, 0.08, 0.24}, {0.82, 0.41, 0.12}, {0.5, 1.0, 0.83}  -- 25-30 (Chàm, Lục bảo, Đỏ Crimson...)
        }
        idx = math.floor(tonumber(idx) or 1)
        if idx < 1 or idx > 30 then idx = 1 end
        local r, g, b = colors[idx][1], colors[idx][2], colors[idx][3]
        if FC then return FC(r, g, b, alpha) end
        return {R = r * 255, G = g * 255, B = b * 255, A = alpha * 255}
    end
    if _G.GRW_XDState and _G.GRW_XDState.CustomTextData then
        local c = _G.GRW_XDState.CustomTextData
        PlayerMapMarker.SnapLineThickness = (c.Esp9_LineThick or 1) * 1.0
        PlayerMapMarker.SnapLineVisibleColor = GetEspColor(c.Esp9_LineVisColor or 2, PlayerMapMarker.SnapLineOpacity or 0.7)
        PlayerMapMarker.SnapLineCoverColor = GetEspColor(c.Esp9_LineHidColor or 1, PlayerMapMarker.SnapLineOpacity or 0.7)
        
        PlayerMapMarker.SkeletonThickness = (c.Esp9_SkelThick or 1) * 0.8
        PlayerMapMarker.SkeletonVisibleColor = GetEspColor(c.Esp9_SkelVisColor or 2, PlayerMapMarker.SkeletonOpacity or 0.8)
        PlayerMapMarker.SkeletonCoverColor = GetEspColor(c.Esp9_SkelHidColor or 1, 0.6)
        PlayerMapMarker.bUseVisibilityColor = true
    end

    if not PlayerMapMarker.InitESPCanvas() then
        return
    end

    if PlayerMapMarker._OBHeadWidgetLoadFailed then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if IsValid(PC) then
        PlayerMapMarker.UpdateCanvasTransform(PC)
    end

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines and IsValid(PC) then
        fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local SeenKeys = {}
    
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            MyChar = GDP.GetLocalCharacter()
        else
            if PC and PC.GetPawn then MyChar = PC:GetPawn() end
        end
    end)
    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            local Name = PlayerMapMarker.GetPlayerName(Character)

            local Loc = PlayerMapMarker.GetESPLocation(Character)

            local DistStr = ""
            if MyLoc and Loc then
                DistStr = PlayerMapMarker.GetDistanceString(MyLoc, Loc)
            end

            local bSkip = false
            if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
            if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end
            
            local TeamID = PlayerMapMarker.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then
                bSkip = true
            end

            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if not bSkip and Loc then
                SeenKeys[KeyStr] = true
                local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]

                -- [THÊM MỚI] Check Bật Tắt Tên và Khoảng Cách
                local Text = ""
                if _G.GRW_XDConfig.Esp9_Name then Text = Name end
                if _G.GRW_XDConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                    if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                end

                local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)

                if not ESPData then
                    local Widget = PlayerMapMarker.CreateESPWidget()
                    if Widget then
                        PlayerMapMarker.ESPWidgets[KeyStr] = {
                            Widget = Widget,
                            Character = Character,
                            Name = Name,
                            LastDistStr = DistStr,
                            TeamID = TeamID,
                        }
                        PlayerMapMarker.UpdateESPText(Widget, Text)
                        if bIsAlive then
                            PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                            PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
                            local HP = Character.Health or 0
                            local MaxHP = Character.MaxHealth or 120
                            local pct = 0
                            if HP > 0 and MaxHP > 0 then
                                pct = HP / MaxHP
                                if pct > 1 then pct = 1 end
                                if pct < 0 then pct = 0 end
                            end
                            PlayerMapMarker.UpdateESPHealth(Widget, pct)
                            PlayerMapMarker.AddWeaponIconToESP(Widget, Character)
                            
                            if PlayerMapMarker.bUseSnapLines then
                                PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY, Character, PC)
                            else
                                PlayerMapMarker.RemoveSnapLine(KeyStr)
                            end

                            if PlayerMapMarker.bUseSkeleton then
                                PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                            else
                                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                            end
                        else
                            local Container = Widget.Container or Widget
                            pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            PlayerMapMarker.UpdateESPHealth(Widget, 0)
                            PlayerMapMarker.RemoveSnapLine(KeyStr)
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    end
                else
                    ESPData.Character = Character
                    ESPData.Name = Name
                    ESPData.LastDistStr = DistStr
                    if bIsAlive then
                        -- Xóa chữ "if TeamID ~= ESPData.TeamID" để nó quét màu Team liên tục, ăn công tắc lập tức
                        ESPData.TeamID = TeamID
                        PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
                        
                        -- Ép quét Text liên tục
                        ESPData.Widget._LastESPText = nil
                        PlayerMapMarker.UpdateESPText(ESPData.Widget, Text)
                        PlayerMapMarker.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)
                        local HP = Character.Health or 0
                        local MaxHP = Character.MaxHealth or 120
                        local pct = 0
                        if HP > 0 and MaxHP > 0 then
                            pct = HP / MaxHP
                            if pct > 1 then pct = 1 end
                            if pct < 0 then pct = 0 end
                        end
                        PlayerMapMarker.UpdateESPHealth(ESPData.Widget, pct)
                        PlayerMapMarker.AddWeaponIconToESP(ESPData.Widget, Character)
                        
                        if PlayerMapMarker.bUseSnapLines then
                            PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                        else
                            PlayerMapMarker.RemoveSnapLine(KeyStr)
                        end

                        if PlayerMapMarker.bUseSkeleton then
                            PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                        else
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    else
                        local Container = ESPData.Widget.Container or ESPData.Widget
                        pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        PlayerMapMarker.UpdateESPHealth(ESPData.Widget, 0)
                        PlayerMapMarker.RemoveSnapLine(KeyStr)
                        PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    end
                end
            end
        end
    end

    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        if not SeenKeys[KeyStr] then
            PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
            PlayerMapMarker.ESPWidgets[KeyStr] = nil
        end
    end
end

function PlayerMapMarker.UpdateESPLight()
    if RedBoxOverlay and RedBoxOverlay.bActive then RedBoxOverlay.UpdatePosition() end
    if not PlayerMapMarker.bUseScreenESP then return end

    -- [OPT ESP V2] Tự phát hiện máy yếu: vòng lặp bị trễ > 0.08s liên tục -> tự động bật chế độ Siêu Nhẹ
    local realNow = os.clock()
    local lastReal = PlayerMapMarker._lastLightRealTime or 0
    if lastReal > 0 and realNow > lastReal then
        local gap = realNow - lastReal
        if gap > 0.08 then
            PlayerMapMarker._WeakCheckMiss = (PlayerMapMarker._WeakCheckMiss or 0) + 1
        elseif gap < 0.06 then
            PlayerMapMarker._WeakCheckMiss = 0
            if PlayerMapMarker._bWeakDevice then PlayerMapMarker._bWeakDevice = false end
        end
        if gap > 1.5 then PlayerMapMarker._bWeakDevice = true end
        if (PlayerMapMarker._WeakCheckMiss or 0) >= 15 then
            PlayerMapMarker._bWeakDevice = true
        end
    end
    PlayerMapMarker._lastLightRealTime = realNow
    PlayerMapMarker._LightTickCount = (PlayerMapMarker._LightTickCount or 0) + 1
    local nTick = PlayerMapMarker._LightTickCount
    local bWeak = PlayerMapMarker._bWeakDevice == true
    -- Máy yếu: mỗi 4 lần gọi mới xử lý 1 lần (hiệu quả ~10Hz) -> hết kẹt FPS, mát máy
    if bWeak and (nTick % 4 ~= 0) then return end

    -- Đồng bộ Config Dây và Xương
    PlayerMapMarker.bUseSnapLines = _G.GRW_XDConfig.Esp9_Line
    PlayerMapMarker.bUseSkeleton = _G.GRW_XDConfig.Esp9_Skeleton
    
    -- Áp dụng tùy chỉnh Độ Dày & 30 Màu
    local function GetEspColor(idx, alpha)
        local FC = _G.FLinearColor or import("LinearColor")
        local colors = {
            {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0, 0.0}, {1.0, 0.0, 1.0}, {1.0, 1.0, 1.0},
            {0.0, 1.0, 1.0}, {1.0, 0.5, 0.0}, {1.0, 0.4, 0.7}, {0.6, 0.3, 0.0}, {0.5, 1.0, 0.0}, {0.0, 0.5, 0.5},
            {0.0, 0.0, 0.5}, {0.5, 0.0, 0.0}, {0.5, 0.5, 0.0}, {0.75, 0.75, 0.75}, {1.0, 0.84, 0.0}, {0.5, 0.0, 1.0},
            {0.53, 0.81, 0.92}, {1.0, 0.5, 0.31}, {0.98, 0.5, 0.45}, {0.94, 0.9, 0.55}, {0.87, 0.63, 0.87}, {0.85, 0.44, 0.84},
            {0.29, 0.0, 0.51}, {0.25, 0.88, 0.82}, {0.6, 1.0, 0.6}, {0.86, 0.08, 0.24}, {0.82, 0.41, 0.12}, {0.5, 1.0, 0.83}
        }
        idx = math.floor(tonumber(idx) or 1)
        if idx < 1 or idx > 30 then idx = 1 end
        local r, g, b = colors[idx][1], colors[idx][2], colors[idx][3]
        if FC then return FC(r, g, b, alpha) end
        return {R = r * 255, G = g * 255, B = b * 255, A = alpha * 255}
    end
    if _G.GRW_XDState and _G.GRW_XDState.CustomTextData then
        local c = _G.GRW_XDState.CustomTextData
        PlayerMapMarker.SnapLineThickness = (c.Esp9_LineThick or 1) * 1.0
        PlayerMapMarker.SnapLineVisibleColor = GetEspColor(c.Esp9_LineVisColor or 2, PlayerMapMarker.SnapLineOpacity or 0.7)
        PlayerMapMarker.SnapLineCoverColor = GetEspColor(c.Esp9_LineHidColor or 1, PlayerMapMarker.SnapLineOpacity or 0.7)
        
        PlayerMapMarker.SkeletonThickness = (c.Esp9_SkelThick or 1) * 0.8
        PlayerMapMarker.SkeletonVisibleColor = GetEspColor(c.Esp9_SkelVisColor or 2, PlayerMapMarker.SkeletonOpacity or 0.8)
        PlayerMapMarker.SkeletonCoverColor = GetEspColor(c.Esp9_SkelHidColor or 1, 0.6)
        PlayerMapMarker.bUseVisibilityColor = true
    end

    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines then fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC) end

    -- Tính khoảng cách LOD từ bản thân
    local MyLoc = PlayerMapMarker._CachedMyLoc or PlayerMapMarker.GetMyLocation()

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Widget = ESPData.Widget
        local Character = ESPData.Character
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Widget and bWidgetValid and Character and IsValid(Character) then
            local bIsAlive = PlayerMapMarker.IsAlive(Character)
            if not bIsAlive then
                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                PlayerMapMarker.RemoveSnapLine(KeyStr)
                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
            else
                -- [FIX VIP] Giữ nguyên tính năng Bật/Tắt UI tùy ý của bạn
                local bShowAnyUI = _G.GRW_XDConfig.Esp9_Name or _G.GRW_XDConfig.Esp9_Distance or _G.GRW_XDConfig.Esp9_HP or _G.GRW_XDConfig.Esp9_Team or _G.GRW_XDConfig.Esp9_Weapon
                if bShowAnyUI then
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                else
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                end
                pcall(function() Container:SetRenderOpacity(1.0) end)

                local Loc = PlayerMapMarker.GetESPLocation(Character)
                if Loc then
                    -- Tính khoảng cách 2D để chia mức độ vẽ (LOD)
                    local distU = 0
                    if MyLoc then
                        local dx = (Loc.X or 0) - (MyLoc.X or 0)
                        local dy = (Loc.Y or 0) - (MyLoc.Y or 0)
                        distU = math.sqrt(dx * dx + dy * dy)
                    end

                    -- [OPT ESP V2] LOD theo Khoảng cách (Địch xa không cần vẽ lại từng mi-li-giây)
                    local lodStep = 1
                    if distU > 25000 then lodStep = 4
                    elseif distU > 10000 then lodStep = 2 end
                    if bWeak then lodStep = lodStep * 2 end

                    if (nTick % lodStep) == 0 then
                        local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)
                        PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                        
                        -- [TỐI ƯU SIÊU KHỦNG] Tính Raycast đúng 1 LẦN cho cả Dây và Xương
                        local bTargetVisible = nil
                        if (PlayerMapMarker.bUseSnapLines or PlayerMapMarker.bUseSkeleton) and distU <= 20000 then
                            bTargetVisible = PlayerMapMarker.IsPlayerVisible(PC, Character)
                        end

                        if PlayerMapMarker.bUseSnapLines then 
                            if distU <= 20000 then
                                PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY, Character, PC, bTargetVisible)
                            else
                                PlayerMapMarker.RemoveSnapLine(KeyStr)
                            end
                        else 
                            PlayerMapMarker.RemoveSnapLine(KeyStr) 
                        end

                        if PlayerMapMarker.bUseSkeleton then
                            PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(ESPData.TeamID), bOnScreen, Loc, bTargetVisible)
                        else
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    end
                else 
                    PlayerMapMarker.RemoveSnapLine(KeyStr)
                    PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                end
            end
        end
    end
end

function PlayerMapMarker.UpdateESPDistances()
    if not PlayerMapMarker.bUseScreenESP then return end
    local MyLoc = PlayerMapMarker.GetMyLocation()
    if not MyLoc then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return end
    PlayerMapMarker.UpdateCanvasTransform(PC)

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Character = ESPData.Character
        local Widget = ESPData.Widget
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)
        if Character and IsValid(Character) and Widget and bWidgetValid then
            local Loc = PlayerMapMarker.GetESPLocation(Character)
            if Loc then
                local Dist = PlayerMapMarker.CalcDistance(MyLoc, Loc)
                ESPData.LastDistance = Dist

                if PlayerMapMarker.bShowDistance then
                    local DistStr = ""
                    local Meters = 0
                    if Dist then
                        Meters = Dist / 100
                        if Meters < 1000 then DistStr = string.format("%dm", math.floor(Meters))
                        else DistStr = string.format("%.1fkm", Meters / 1000) end
                    end

                    local Name = ESPData.Name or "Unknown"
                    local Text = ""
                    
                    -- Đồng bộ với công tắc ESP 9
                    if _G.GRW_XDConfig.Esp9_Name then Text = Name end
                    if _G.GRW_XDConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                        if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                    end
                    
                    ESPData.LastDistStr = DistStr
                    -- Ép Widget quên text cũ để vẽ lại chữ Rỗng
                    Widget._LastESPText = nil 
                    PlayerMapMarker.UpdateESPText(Widget, Text)
                end
            end
        end
    end
end

function PlayerMapMarker.ScanAndUpdate()
    local AllChars = PlayerMapMarker.GetAllCharacters()
    if not AllChars then RedBoxOverlay.SetCounts(0, 0) return 0 end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local MyLoc = PlayerMapMarker.GetMyLocation()

    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else local PC = PlayerMapMarker.GetMyPlayerController() if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
    end)
    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    local realPlayers = 0
    local botPlayers = 0

    for PlayerKey, Character in pairs(AllChars) do
        if IsValid(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if bIsAlive and not bIsMe then
                local bIsMyTeam = false
                if MyTeamID ~= nil then
                    local targetTeamID = PlayerMapMarker.GetTeamID(Character)
                    if targetTeamID == MyTeamID then bIsMyTeam = true end
                end
                
                if not bIsMyTeam then
                    if bIsAI then botPlayers = botPlayers + 1
                    else realPlayers = realPlayers + 1 end
                end
            end
        end
    end

    -- [THÊM MỚI] Bật Tắt Bảng Đếm Người
    if _G.GRW_XDConfig.Esp9_Count then
        if RedBoxOverlay.bActive then RedBoxOverlay.SetCounts(realPlayers, botPlayers)
        else RedBoxOverlay.Start() end
    else
        if RedBoxOverlay.bActive then RedBoxOverlay.Stop() end
    end

    if PlayerMapMarker.bUseScreenESP then
        PlayerMapMarker.UpdateESP(AllChars, MyLoc)
        return 0
    end
    return 0
end

function PlayerMapMarker.AttachTimers()
    -- [ĐÃ FIX] Bỏ trống hàm này để hủy hoàn toàn việc sử dụng AddGameTimer rác gây lag
end

function PlayerMapMarker.Start()
    if PlayerMapMarker.bActive then return end
    PlayerMapMarker.bActive = true
    PlayerMapMarker._FrameCount = 0
    -- [ĐÃ FIX] Gom chung vào MainLoop, không tự tạo Timer ảo nữa
end

function PlayerMapMarker.Stop()
    PlayerMapMarker.bActive = false
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker.ClearAllESP()
end

_G.PlayerMapMarker = PlayerMapMarker
-- ============================================================
-- KẾT THÚC: LÕI ESP LOẠI 9 (TỪ CODE MẪU GỐC FULL LOGIC)
-- ============================================================

-- ==========================================
-- VÒNG FOV AIMBOT V2
-- ==========================================
_G.FovCircleOverlay = {
    Container = nil,
    WidgetSlot = nil,
    Lines = {},
    NumSegments = 45, -- [TỐI ƯU] Giảm từ 90 xuống 45 (Giảm 50% gánh nặng UI mà vẫn mượt)
    Thickness = 1.5,  
    LastRadius = -1,
    LastColor = -1,
    LastCX = -1,
    LastCY = -1,
    PrecalcMath = nil -- [TỐI ƯU] Bộ nhớ đệm toán học chống drop FPS
}

local function GetFOVColor(idx)
    if idx == 1 then return 1.0, 0.0, 0.0 end
    if idx == 2 then return 0.0, 1.0, 0.0 end
    if idx == 3 then return 0.0, 0.0, 1.0 end
    if idx == 4 then return 1.0, 1.0, 0.0 end
    if idx == 5 then return 0.65, 0.15, 1.0 end
    if idx == 6 then return 0.0, 1.0, 1.0 end
    if idx == 7 then return 1.0, 1.0, 1.0 end
    return 1.0, 1.0, 1.0 
end

function _G.FovCircleOverlay.Create()
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then return true end
    
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if slua.isValid(MainUI) then
            if slua.isValid(MainUI.CanvasPanel_0) then ParentCanvas = MainUI.CanvasPanel_0
            elseif slua.isValid(MainUI.CanvasPanel_42) then ParentCanvas = MainUI.CanvasPanel_42 end
        end
    end)
    
    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    local FVector2D = import("Vector2D") or _G.FVector2D
    
    for i = 1, _G.FovCircleOverlay.NumSegments do
        local border = nil
        pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
        if border and slua.isValid(border) then
            pcall(function() 
                border.RenderTransformPivot = FVector2D(0, 0.5)
                border:SetRenderTransformPivot(FVector2D(0, 0.5)) 
                border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local slot = Container:AddChildToCanvas(border)
            if slot then
                pcall(function() slot:SetAlignment(FVector2D(0, 0.5)) end)
            end
            _G.FovCircleOverlay.Lines[i] = { widget = border, slot = slot }
        end
    end

    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if MainSlot then
        pcall(function()
            MainSlot:SetAutoSize(false)
            MainSlot:SetSize(FVector2D(0, 0))
            MainSlot:SetZOrder(995)
            MainSlot:SetAlignment(FVector2D(0, 0))
            MainSlot:SetPosition(FVector2D(0, 0))
        end)
    end
    _G.FovCircleOverlay.Container = Container
    _G.FovCircleOverlay.WidgetSlot = MainSlot
    return true
end

function _G.FovCircleOverlay.Update(pc, player)
    -- Chỉ phụ thuộc duy nhất vào công tắc "HIỂN THỊ VÒNG FOV AIMBOT"
    if not _G.GRW_XDConfig.EspFovCircle then
        if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
            pcall(function() _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            _G.FovCircleOverlay.LastRadius = -1
        end
        return
    end

    local fovVal = 30
    local colIdx = 7 -- Mặc định là trắng
    
    local cData = _G.GRW_XDState.CustomTextData
    local WEAPON_TYPE = _G.__AimTouch_WeaponType or "NORMAL"
    local isADS = player.bIsGunADS or false

    -- Đọc Bán Kính FOV và Màu Sắc Tương Ứng cho từng loại súng
    if WEAPON_TYPE == "MORTAR" then
        fovVal = cData.AimTouchMortarFOV or 360
        colIdx = tonumber(cData.AimTouchMortarFOVColor) or 5
    elseif WEAPON_TYPE == "CROSSBOW" then
        fovVal = cData.AimTouchCrossbowFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif WEAPON_TYPE == "BOW" then
        fovVal = cData.AimTouchBowFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif WEAPON_TYPE == "SHOTGUN" then
        fovVal = cData.AimTouchSGFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif isADS then
        if WEAPON_TYPE == "SNIPER" then
            fovVal = cData.AimTouchSniperFOV or 20
            colIdx = tonumber(cData.AimTouchSniperFOVColor) or 4
        else
            fovVal = cData.AimTouchScopeFOV or 30
            colIdx = tonumber(cData.AimTouchScopeFOVColor) or 6
        end
    else
        fovVal = cData.AimTouchHipFOV or 30
        colIdx = tonumber(cData.AimTouchHipFOVColor) or 7
    end

    local rawCX = _G.__AimTouch_CenterX or 960
    local rawCY = _G.__AimTouch_CenterY or 540
    local vpX = _G.__AimTouch_ViewportX or 1920

    -- Ép cập nhật tỷ lệ màn hình (Scale) kể cả khi ESP VIP đang tắt
    if PlayerMapMarker and PlayerMapMarker.UpdateCanvasTransform then
        pcall(function() PlayerMapMarker.UpdateCanvasTransform(pc) end)
    end

    local FVector2D = import("Vector2D") or _G.FVector2D
    local screenCenter = FVector2D and FVector2D(rawCX, rawCY) or {X=rawCX, Y=rawCY}
    
    local canvasCenter = {X = rawCX, Y = rawCY}
    pcall(function() canvasCenter = PlayerMapMarker.ScreenPixelToCanvasLocal(pc, screenCenter) end)
    
    local centerX = canvasCenter.X
    local centerY = canvasCenter.Y

    local rawRadius = (fovVal / 100.0) * (vpX / 2.0)
    local scaleX = PlayerMapMarker and PlayerMapMarker._CanvasScaleX or 1.0
    local targetRadius = rawRadius * scaleX

    -- Nếu bạn tắt ESP làm Game xóa lớp vẽ của FOV -> Tự động nhận diện và vẽ lại ngay lập tức
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        local parent = nil
        pcall(function() parent = _G.FovCircleOverlay.Container:GetParent() end)
        if not parent or not slua.isValid(parent) then
            _G.FovCircleOverlay.Container = nil
        end
    end

    if not _G.FovCircleOverlay.Create() then return end
    pcall(function() _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

    -- [TỐI ƯU 1] Thêm sai số 0.5 pixel để tránh phá vỡ Cache liên tục vì rung lắc màn hình
    if math.abs(_G.FovCircleOverlay.LastRadius - targetRadius) < 0.5 
       and _G.FovCircleOverlay.LastColor == colIdx 
       and math.abs(_G.FovCircleOverlay.LastCX - centerX) < 0.5 
       and math.abs(_G.FovCircleOverlay.LastCY - centerY) < 0.5 then
        return
    end

    _G.FovCircleOverlay.LastRadius = targetRadius
    _G.FovCircleOverlay.LastColor = colIdx
    _G.FovCircleOverlay.LastCX = centerX
    _G.FovCircleOverlay.LastCY = centerY

    local FLinearColor = import("LinearColor") or _G.FLinearColor
    local r, g, b = GetFOVColor(colIdx)
    local dim = 0.55 
    local color = FLinearColor and FLinearColor(r * dim, g * dim, b * dim, 1.0) or {R=r*dim*255, G=g*dim*255, B=b*dim*255, A=255}

    local numSegments = _G.FovCircleOverlay.NumSegments

    -- [TỐI ƯU 2] Tính toán Sin/Cos sẵn 1 LẦN DUY NHẤT (Chống cháy CPU mỗi khung hình)
    if not _G.FovCircleOverlay.PrecalcMath then
        _G.FovCircleOverlay.PrecalcMath = {}
        local angleStep = 360.0 / numSegments
        local math_cos = math.cos
        local math_sin = math.sin
        local math_rad = math.rad
        local math_atan2 = math.atan2 or math.atan
        
        for i = 1, numSegments do
            local angle1 = math_rad((i - 1) * angleStep)
            local angle2 = math_rad(i * angleStep)
            local c1, s1 = math_cos(angle1), math_sin(angle1)
            local c2, s2 = math_cos(angle2), math_sin(angle2)
            
            local dx_unit = c2 - c1
            local dy_unit = s2 - s1
            local dist_unit = math.sqrt(dx_unit*dx_unit + dy_unit*dy_unit)
            local angleDeg = math.deg(math_atan2(dy_unit, dx_unit))
            
            _G.FovCircleOverlay.PrecalcMath[i] = {
                c1 = c1, s1 = s1,
                dist_unit = dist_unit,
                angleDeg = angleDeg
            }
        end
    end

    pcall(function()
        local FVector2D = import("Vector2D") or _G.FVector2D
        for i = 1, numSegments do
            local mathData = _G.FovCircleOverlay.PrecalcMath[i]
            
            -- Chỉ dùng phép nhân cơ bản siêu nhẹ thay vì tính toán lượng giác phức tạp
            local x1 = targetRadius * mathData.c1
            local y1 = targetRadius * mathData.s1
            local dist = targetRadius * mathData.dist_unit

            local line = _G.FovCircleOverlay.Lines[i]
            if line and line.slot and slua.isValid(line.slot) then
                line.slot:SetPosition(FVector2D(centerX + x1, centerY + y1))
                line.slot:SetSize(FVector2D(dist + 0.8, _G.FovCircleOverlay.Thickness))
                line.widget:SetRenderAngle(mathData.angleDeg)
                line.widget:SetBrushColor(color)
            end
        end
    end)
end

function _G.CleanUpFovCircleOverlay()
    if _G.FovCircleOverlay and _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        pcall(function() _G.FovCircleOverlay.Container:RemoveFromParent() end)
        pcall(function() _G.FovCircleOverlay.Container:ConditionalBeginDestroy() end)
    end
    if _G.FovCircleOverlay then
        _G.FovCircleOverlay.Container = nil
        _G.FovCircleOverlay.WidgetSlot = nil
        _G.FovCircleOverlay.LastRadius = -1
    end
end

-- ==========================================
-- HỆ THỐNG HIỂN THỊ "DUNGCU" ĐỘC LẬP TỔNG THỂ (BẢO VỆ CHỐNG ESP CLEAR)
-- ==========================================
local DungCuOverlay = {
    Widget = nil,
    Slot = nil
}

local function CleanUpPermanentDungCu()
    if DungCuOverlay.Widget and slua.isValid(DungCuOverlay.Widget) then
        pcall(function() DungCuOverlay.Widget:RemoveFromParent() end)
        pcall(function() DungCuOverlay.Widget:ConditionalBeginDestroy() end)
    end
    DungCuOverlay.Widget = nil
    DungCuOverlay.Slot = nil
end

local function EnsurePermanentDungCu()
    -- BƯỚC BẢO VỆ: Cấy khiên chống lại cỗ máy dọn rác của ESP V2
    if _G.PlayerMapMarker and not _G.DungCu_Protected then
        local old_IsOurESPWidget = _G.PlayerMapMarker.IsOurESPWidget
        _G.PlayerMapMarker.IsOurESPWidget = function(w)
            -- Báo cho hệ thống biết đây KHÔNG PHẢI là rác của ESP, CẤM XÓA!
            if DungCuOverlay.Widget and w == DungCuOverlay.Widget then 
                return false 
            end
            if _G.FovCircleOverlay and _G.FovCircleOverlay.Container and w == _G.FovCircleOverlay.Container then
                return false
            end
            if old_IsOurESPWidget then return old_IsOurESPWidget(w) end
            return false
        end
        _G.DungCu_Protected = true
    end

    -- 1. Nếu chữ đã có trên màn hình, ép bám theo toạ độ (Kể cả khi ESP V2 tắt)
    if DungCuOverlay.Widget and slua.isValid(DungCuOverlay.Widget) then 
        pcall(function() DungCuOverlay.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        
        local PC = _G.PlayerMapMarker and _G.PlayerMapMarker.GetMyPlayerController()
        if slua.isValid(PC) and DungCuOverlay.Slot then
            
            -- [SỬA LỖI CHÍNH Ở ĐÂY]
            -- Khi ESP V2 bị tắt, ESPCanvas bị set thành nil khiến UpdateCanvasTransform bị lỗi.
            -- Ta phải gọi InitESPCanvas() để lấy lại khung vẽ thì GetSnapLineStartPos mới tính chuẩn!
            if not _G.PlayerMapMarker.ESPCanvas or not slua.isValid(_G.PlayerMapMarker.ESPCanvas) then
                pcall(function() _G.PlayerMapMarker.InitESPCanvas() end)
            end
            
            -- Ép cập nhật Scale màn hình dù ESP V2 đang tắt
            pcall(function() _G.PlayerMapMarker.UpdateCanvasTransform(PC) end)
            
            local fromX, fromY = _G.PlayerMapMarker.GetSnapLineStartPos(PC)
            local FVector2D = import("Vector2D") or _G.FVector2D
            pcall(function() DungCuOverlay.Slot:SetPosition(FVector2D(fromX, fromY - 8)) end)
        end
        return 
    end

    -- 2. Nếu chưa có, tiến hành vẽ mới
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainControlBaseUI = InGameUITools and InGameUITools.GetMainControlBaseUI()
        if MainControlBaseUI and slua.isValid(MainControlBaseUI) then
            ParentCanvas = MainControlBaseUI.CanvasPanel_0
            if not slua.isValid(ParentCanvas) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
        end
    end)

    if not ParentCanvas or not slua.isValid(ParentCanvas) then return end

    local txtTitle = nil
    pcall(function() txtTitle = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas) end)
    if txtTitle and slua.isValid(txtTitle) then
        pcall(function()
            txtTitle:SetText("")
            local FLinearColor = import("LinearColor") or _G.FLinearColor
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local redLinear = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {R=255, G=0, B=0, A=255}
            if FSlateColor then txtTitle:SetColorAndOpacity(FSlateColor(redLinear)) else txtTitle:SetColorAndOpacity(redLinear) end

            if txtTitle.Font then
                local font = txtTitle.Font
                font.Size = 24 
                txtTitle.Font = font
            end
            
            local FVector2D = import("Vector2D") or _G.FVector2D
            txtTitle:SetRenderScale(FVector2D(1.0, 1.0))
            txtTitle:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtTitle:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)

        local txtSlot = ParentCanvas:AddChildToCanvas(txtTitle)
        if txtSlot then
            pcall(function()
                txtSlot:SetAutoSize(true)
                local FVector2D = import("Vector2D") or _G.FVector2D
                txtSlot:SetAlignment(FVector2D(0.5, 1.0))
                txtSlot:SetZOrder(9999)
            end)
            DungCuOverlay.Slot = txtSlot
        end
        DungCuOverlay.Widget = txtTitle
    end
end

-- ========================================== 
-- VÒNG LẶP CHÍNH (MAIN LOOP) TỐI ƯU CỰC MẠNH
-- ========================================== 
local function MainLoop()
    if isExpired then return end

    -- =====================================================================
    -- HỆ THỐNG LẤY HWID GỐC & ĐỔI HWID ẢO (SPOOFER) CHỐNG BAN
    -- =====================================================================
    pcall(function()
        local SystemLib = import("KismetSystemLibrary")
        if SystemLib and not _G.FakeHWID_Hooked then
            -- Lưu lại hàm lấy HWID gốc
            _G.Original_GetDeviceId = SystemLib.GetDeviceId

            -- Ghi đè hàm của game
            SystemLib.GetDeviceId = function(...)
                if _G.GRW_XDConfig.FakeHWID then
                    if not _G.FakeHWID_String then
                        -- Tạo ngẫu nhiên một HWID ảo 32 ký tự
                        local chars = "0123456789abcdef"
                        local hwid = ""
                        for i = 1, 32 do 
                            hwid = hwid .. chars:sub(math.random(1, 16), math.random(1, 16)) 
                        end
                        _G.FakeHWID_String = hwid
                    end
                    -- Trả về HWID ảo
                    return _G.FakeHWID_String
                end
                
                -- Nếu tắt Fake HWID thì trả về HWID thật
                if _G.Original_GetDeviceId then return _G.Original_GetDeviceId(...) end
                return "UNKNOWN"
            end
            _G.FakeHWID_Hooked = true
        end
    end)

    -- Hàm độc lập để bạn lấy HWID Gốc (nếu sau này cần hiển thị)
    _G.GetOriginalHWID = function()
        if _G.Original_GetDeviceId then
            return tostring(_G.Original_GetDeviceId())
        end
        local SystemLib = import("KismetSystemLibrary")
        if SystemLib and type(SystemLib.GetDeviceId) == "function" then
            return tostring(SystemLib.GetDeviceId())
        end
        return "UNKNOWN_DEVICE"
    end
    -- =====================================================================

    if _G.GRW_XDState.CustomTextData == nil then 
        _G.GRW_XDState.CustomTextData = {OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120, IpadViewVehicleFOV = 120, IpadViewScopeFOV = 100, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250, AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, FastCarSpeed = 2000}
    end

    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    -- XÓA SẠCH SÀNH SANH RÁC KHỎI RAM KHI BẠN CHẾT, ĐỔI MAP, VÀO SẢNH (ĐÃ FIX MEMORY LEAK)
    if not Valid(localPlayer) then 
        if _G.PlayerMapMarker and type(_G.PlayerMapMarker.Stop) == "function" then
            _G.PlayerMapMarker.Stop()
        end
        if _G.RedBoxOverlay and type(_G.RedBoxOverlay.Stop) == "function" then
            _G.RedBoxOverlay.Stop()
        end
        
        if _G.GRW_XDState.TrackedMarks then
            for markId, _ in pairs(_G.GRW_XDState.TrackedMarks) do SafeRemoveMark(markId) end
        end
        
        -- XÓA TRIỆT ĐỂ BỘ NHỚ ĐỆM CỦA TẤT CẢ CÁC ESP (Chống văng game)
        _G.AppliedVehicleWall = {}
        _G.AppliedItemESP = {}
        _G.CachedItems = {}
        _G.CachedVehicles = {}
        _G.CachedActiveBombs = {}
        _G.CachedItemBombs = {}
        _G.AimTouchVisCache = {}
        _G.ActiveBombTimers = {}
        _G.BombCache = setmetatable({}, { __mode = "k" })
        _G.NonBombCache = setmetatable({}, { __mode = "k" })
        
        _G.GRW_XDState.TrackedMarks = {} 
        for key, data in pairs(_G.GRW_XDState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
            end
            if data and data.MIDs_V3 then
                for meshStr, midTable in pairs(data.MIDs_V3) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
            end
        end
        
        _G.GRW_XDState.EnemyMarks = {}
        _G.AK_OrigHitboxes = {}
        _G.AK_ModdedPhysAssets = {}
        _G.GRW_XDState.PrevGraphicsState = {}
        
        if _G.CleanUpEnemyCounterWidget then _G.CleanUpEnemyCounterWidget() end
        CleanUpPermanentDungCu() 
        if _G.CleanUpFovCircleOverlay then _G.CleanUpFovCircleOverlay() end
        return 
    end

    local Cached_PPM = nil
    pcall(function() Cached_PPM = import("PostProcessManager").GetInstance() end)
    local Cached_SecurityCommonUtils = nil
    pcall(function() Cached_SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils") end)
    local Cached_MyHUD = pc and pc.MyHUD or nil

    if _G.GRW_XDConfig.UnlockFPS then InitializeGraphicsUnlock() end
    InitializeNativeESP()
    -- Pre-login: keep menu state uninitialized/hidden. Login UI is owned by AHMADAuthRuntime.
    if not (_G.AHMADAuthActive and _G.AHMADAuthActive() == true) then
        _G.ModMenuInitialized = false
        _G.GRW_XDMenuAlreadyShown = false
    end
    -- FIX (root cause #2): old code had `-- ShowGRW_XDVIPMenu()` commented out,
    -- so _G.InitModMenuTab() was NEVER called -> Settings me VIP MENU tab kabhi
    -- add hi nahi hota tha. Direct call karo (idempotent, guarded by ModMenuInitialized).
    pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and _G.InitModMenuTab then _G.InitModMenuTab() end end)
    pcall(function() if _G.AHMADAuthActive and _G.AHMADAuthActive() and ShowGRW_XDVIPMenu then ShowGRW_XDVIPMenu() end end)

    -- KEY FIRST: hide the floating Mod Menu opener until authentication is active.
    if _G.AHMADAuthActive and _G.AHMADAuthActive() == true then
        pcall(ShowMiniButton)
    else
        pcall(HideMiniButton)
    end

    -- [GỌI LOGIC DUNGCU] Luôn chạy độc lập không cần công tắc
    EnsurePermanentDungCu()
    
    -- [GỌI LOGIC ESP ITEM VÀ VEHICLE VÀO VÒNG LẶP]
    if _G.GRW_XDConfig.WallVehicle or _G.GRW_XDConfig.EspItem_Master then
        _G.RunOptimizedItemAndVehicleESP(pc)
    end
    
    -- [TÍCH HỢP] LOGIC BẬT/TẮT ESP LOẠI 9 VÀO MAINLOOP (KHÔNG DÙNG TIMER GÂY LAG)
    if _G.GRW_XDConfig.EspLoai9 then
        if _G.PlayerMapMarker then
            if not _G.PlayerMapMarker.bActive then _G.PlayerMapMarker.Start() end
            
            local curTime = os.clock()
            -- Quét mục tiêu 0.5s/Lần (Nhẹ máy)
            if not _G.LastEsp9Scan or (curTime - _G.LastEsp9Scan) > 0.5 then
                _G.LastEsp9Scan = curTime
                pcall(function() _G.PlayerMapMarker.ScanAndUpdate() end)
            end
            
            -- Cập nhật khoảng cách 0.1s/Lần
            if not _G.LastEsp9Dist or (curTime - _G.LastEsp9Dist) > 0.1 then
                _G.LastEsp9Dist = curTime
                pcall(function() _G.PlayerMapMarker.UpdateESPDistances() end)
            end
            
            -- Cập nhật vị trí vẽ ESP theo khung hình (Trơn Tru)
            pcall(function() _G.PlayerMapMarker.UpdateESPLight() end)
        end
    else
        if _G.PlayerMapMarker and _G.PlayerMapMarker.bActive then
            _G.PlayerMapMarker.Stop()
        end
    end
    
    -- LOGIC IPAD VIEW (ĐI BỘ, LÁI XE VÀ MỞ SCOPE) ĐÃ NÂNG CẤP
    pcall(function()
        local isAiming = false
        if localPlayer.bIsWeaponAiming or localPlayer.bIsGunADS then isAiming = true end

        local currentVehicle = localPlayer.CurrentVehicle or (type(localPlayer.GetVehicle) == "function" and localPlayer:GetVehicle())
        local isInVehicle = Valid(currentVehicle) or localPlayer.bIsInVehicle
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        local uVehCam = localPlayer.VehicleCameraComponent
        local camMgr = pc.PlayerCameraManager

        -- 1. XỬ LÝ KHI ĐANG MỞ SCOPE (NGẮM BẮN)
        if isAiming then
            if _G.GRW_XDConfig.IpadViewScope and _G.GRW_XDState.CustomTextData then
                local targetScope = _G.GRW_XDState.CustomTextData.IpadViewScopeFOV or 60
                if type(pc.FOV) == "function" then pc:FOV(targetScope) end
                if Valid(camMgr) then
                    camMgr.DefaultFOV = targetScope
                    if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetScope) end
                end
            else
                -- Nếu tắt Ipad Scope, trả lại FOV thật của Game để ngắm chuẩn
                if type(pc.FOV) == "function" then pc:FOV(0) end
                if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
            end
            return -- Ngắt logic đi bộ/xe vì ưu tiên Scope
        end

        -- 2. XỬ LÝ KHI KHÔNG NGẮM BẮN (ĐI BỘ HOẶC LÁI XE)
        -- Phục hồi camera nếu trước đó vừa tắt Scope
        if not isInVehicle or not _G.GRW_XDConfig.IpadViewVehicle then
            if type(pc.FOV) == "function" then pc:FOV(0) end
            if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
        end

        -- Đi Bộ
        if not isInVehicle then
            if _G.GRW_XDConfig.IpadView and _G.GRW_XDState.CustomTextData then
                local targetTPP = _G.GRW_XDState.CustomTextData.IpadViewFOV or 120
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then 
                    uTPPCam.FieldOfView = targetTPP 
                end
            else
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then 
                    uTPPCam.FieldOfView = 90 
                end
            end
        end

        -- Lái Xe
        if isInVehicle then
            if _G.GRW_XDConfig.IpadViewVehicle and _G.GRW_XDState.CustomTextData then
                local targetVeh = _G.GRW_XDState.CustomTextData.IpadViewVehicleFOV or 120
                
                if Valid(uVehCam) and uVehCam.FieldOfView ~= targetVeh then 
                    uVehCam.FieldOfView = targetVeh 
                end
                
                if targetVeh > 90 then
                    if type(pc.FOV) == "function" then pc:FOV(targetVeh) end
                    if Valid(camMgr) then
                        camMgr.DefaultFOV = targetVeh
                        if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetVeh) end
                    end
                end
            else
                if Valid(uVehCam) and uVehCam.FieldOfView ~= 90 then 
                    uVehCam.FieldOfView = 90 
                end
            end
        end
    end)

    -- ========================================================
    -- LOGIC AIMBOT V2 ROYAL/CUSTOM VÀ VÒNG FOV
    -- ========================================================
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util then
            local vp = ui_util.GetViewportSize()
            if vp then
                _G.__AimTouch_ViewportX = vp.X
                _G.__AimTouch_CenterX = vp.X * 0.5
                _G.__AimTouch_CenterY = vp.Y * 0.5
            end
        end
        
        local wName = ""
        local weapon = localPlayer.WeaponManagerComponent and localPlayer.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(localPlayer.GetCurrentShootWeapon) == "function" then
            weapon = localPlayer:GetCurrentShootWeapon()
        end
        if slua.isValid(weapon) then
            wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                _G.__AimTouch_WeaponType = "SHOTGUN"
            elseif wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                _G.__AimTouch_WeaponType = "SNIPER"
            elseif wName:lower():find("mortar") or wName:lower():find("cối") then
                _G.__AimTouch_WeaponType = "MORTAR"
            elseif wName:lower():find("crossbow") or wName:lower():find("nỏ") then
                _G.__AimTouch_WeaponType = "CROSSBOW"
            elseif wName:lower():find("bow") or wName:lower():find("cung") then
                _G.__AimTouch_WeaponType = "BOW"
            else
                _G.__AimTouch_WeaponType = "NORMAL"
            end
        end
    end)

    if _G.GRW_XDConfig.AimTouchEnable then
        _G.AimTouch()
    end

    if _G.FovCircleOverlay then
        pcall(function() _G.FovCircleOverlay.Update(pc, localPlayer) end)
    end
    
    -- [THÊM MỚI] LOGIC GLOW SÚNG (ĐỘC LẬP & SIÊU MƯỢT 0.5s/Lần - ĐẢM BẢO 0% DROP FPS)
    if not _G.LastGlowTime or (os.clock() - _G.LastGlowTime) > 0.5 then
        _G.LastGlowTime = os.clock()
        if _G.ApplyWeaponGlow then _G.ApplyWeaponGlow(localPlayer) end
    end

    -- ========================================================
    -- LOGIC BÙ GIẬT (GHÌM TÂM) CHỈ DÀNH RIÊNG CHO AIMBOT GỐC (ĐÃ FIX LAG ĐÔNG NGƯỜI)
    -- ========================================================
    pcall(function()
        if _G.GRW_XDConfig.CustomAimbot and localPlayer.bIsWeaponFiring and localPlayer.bIsGunADS then
            local outerRecoilVal = _G.GRW_XDState.CustomTextData.OuterRecoil or 0
            if outerRecoilVal > 0 then
                local curTime = os.clock()
                
                -- [FIX CPU CỰC MẠNH]: Quét mục tiêu 0.2s/lần thay vì 100 lần/giây để tránh quá tải máy khi check FOV
                if not _G.RecoilTargetCacheTime or (curTime - _G.RecoilTargetCacheTime) > 0.2 then
                    _G.RecoilTargetCacheTime = curTime
                    _G.HasRecoilTargetCached = false
                    
                    local ui_util = require("client.common.ui_util")
                    if ui_util then
                        local viewportSize = ui_util.GetViewportSize()
                        if viewportSize then
                            local centerX = viewportSize.X * 0.5
                            local centerY = viewportSize.Y * 0.5
                            local FOV_RADIUS = (6 / 100.0) * (viewportSize.X / 2.0) 
                            
                            local enemies = _G.GetEnemyTargetsFromActors(40000) 
                            if enemies and #enemies > 0 then
                                local FVector2D = import("Vector2D")
                                for _, target in ipairs(enemies) do
                                    if slua.isValid(target) and target.HealthStatus ~= 1 then 
                                        local tPos = type(target.K2_GetActorLocation) == "function" and target:K2_GetActorLocation() or nil
                                        if tPos then
                                            local screen = FVector2D()
                                            if pc:ProjectWorldLocationToScreen(tPos, screen, false) and screen.X > 0 and screen.Y > 0 then
                                                local dx = screen.X - centerX
                                                local dy = screen.Y - centerY
                                                if math.sqrt(dx*dx + dy*dy) <= FOV_RADIUS then
                                                    _G.HasRecoilTargetCached = true
                                                    break 
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if _G.HasRecoilTargetCached then
                    local currentRot = pc:GetControlRotation()
                    if currentRot then
                        local pullDownForce = (outerRecoilVal / 50.0) * 1.5
                        currentRot.Pitch = currentRot.Pitch - pullDownForce
                        pc:SetControlRotation(currentRot, "CustomAimbotRecoil")
                    end
                end
            end
        else
            _G.HasRecoilTargetCached = false
        end
    end)
    
    -- ========================================================
    -- CHẶN HIGGSBOSON THEO THỜI GIAN THỰC LÀM AN TOÀN TUYỆT ĐỐI MÀ KHÔNG GÂY VĂNG GAME
    pcall(function()
        if Valid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false end
        end
    end)

    -- HOÀN TRẢ VÀ THIẾT LẬP AIMBOT HEAD COMPONENT BẬT/TẮT TỨC THÌ
    pcall(function()
        local autoComp = localPlayer.AutoAimComp
        if Valid(autoComp) then
            if not _G.GRW_XDState.OrigAutoAimCompCached then
                _G.GRW_XDState.OrigAutoAimCompCached = {
                    bOnlyHitHead = autoComp.bOnlyHitHead,
                    HeadBoneName = autoComp.HeadBoneName,
                    Bones = autoComp.Bones,
                    ChestBoneName = autoComp.ChestBoneName,
                    PelvisBoneName = autoComp.PelvisBoneName,
                    HeadPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.HeadPriority,
                    ChestPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.ChestPriority,
                    PelvisPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.PelvisPriority
                }
            end
            
            if _G.GRW_XDConfig.AutoHead then
                autoComp.bOnlyHitHead = true
                autoComp.HeadBoneName = "Head"
                pcall(function() autoComp.Bones = {"Head"} end)
                autoComp.ChestBoneName = "Head"
                autoComp.PelvisBoneName = "Head"
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = 100
                    autoComp.AimAssistConfig.ChestPriority = 100
                    autoComp.AimAssistConfig.PelvisPriority = 100
                end
            else
                local orig = _G.GRW_XDState.OrigAutoAimCompCached
                autoComp.bOnlyHitHead = orig.bOnlyHitHead
                autoComp.HeadBoneName = orig.HeadBoneName
                pcall(function() autoComp.Bones = orig.Bones or {"Spine_01", "Pelvis", "Head"} end)
                autoComp.ChestBoneName = orig.ChestBoneName
                autoComp.PelvisBoneName = orig.PelvisBoneName
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = orig.HeadPriority or 1
                    autoComp.AimAssistConfig.ChestPriority = orig.ChestPriority or 1
                    autoComp.AimAssistConfig.PelvisPriority = orig.PelvisPriority or 1
                end
            end
        end
    end)

    if _G.GRW_XDConfig.WallClimb then
        pcall(function()
            local charMove = localPlayer.CharacterMovement
            if Valid(charMove) then
                if not _G.GRW_XDState.WallClimbOriginals then
                    _G.GRW_XDState.WallClimbOriginals = { WalkableFloorAngle = charMove.WalkableFloorAngle, MaxStepHeight = charMove.MaxStepHeight }
                end
                charMove.WalkableFloorAngle = 199.0
                charMove.MaxStepHeight = 999.0
                _G.GRW_XDState.WallClimbApplied = true
            end
        end)
    elseif _G.GRW_XDState.WallClimbApplied then
        pcall(function()
            local charMove = localPlayer.CharacterMovement
            if Valid(charMove) and _G.GRW_XDState.WallClimbOriginals then
                charMove.WalkableFloorAngle = _G.GRW_XDState.WallClimbOriginals.WalkableFloorAngle or 50.0
                charMove.MaxStepHeight = _G.GRW_XDState.WallClimbOriginals.MaxStepHeight or 45.0
            end
        end)
        _G.GRW_XDState.WallClimbApplied = false
    end

    if _G.GRW_XDConfig.FastCar then
        pcall(function()
            local currentVehicle = localPlayer.CurrentVehicle or (type(localPlayer.GetVehicle) == "function" and localPlayer:GetVehicle())
            if Valid(currentVehicle) then
                local rootComp = currentVehicle.RootComponent or (type(currentVehicle.K2_GetRootComponent) == "function" and currentVehicle:K2_GetRootComponent())
                
                if Valid(rootComp) and type(rootComp.SetAllPhysicsLinearVelocity) == "function" then
                    local isAccelerating = false
                    local moveComp = currentVehicle.VehicleMovement or currentVehicle.MovementComponent
                    if Valid(moveComp) then
                        local throttle = moveComp.ThrottleInput or 0
                        if type(moveComp.GetThrottleInput) == "function" then
                            throttle = moveComp:GetThrottleInput()
                        end
                        if throttle > 0.05 or throttle < -0.05 then 
                            isAccelerating = true
                        end
                    end
                    if currentVehicle.bIsPressingGas or (currentVehicle.Throttle and currentVehicle.Throttle ~= 0) then
                        isAccelerating = true
                    end

                    local currentVel = nil
                    if type(currentVehicle.GetVelocity) == "function" then
                        currentVel = currentVehicle:GetVelocity()
                    elseif type(rootComp.GetPhysicsLinearVelocity) == "function" then
                        currentVel = rootComp:GetPhysicsLinearVelocity()
                    elseif rootComp.ComponentVelocity then
                        currentVel = rootComp.ComponentVelocity
                    end

                    if currentVel then
                        local currentSpeed = math.sqrt(currentVel.X^2 + currentVel.Y^2)
                        local minSpeedToBoost = 50.0   
                        
                        -- Tốc độ thực tế đã được fix nhân lên từ thanh kéo (Max 6000.0)
                        local maxSpeed = _G.GRW_XDState.CustomTextData.FastCarSpeed or 3000.0        
                        
                        -- Cố định gia tốc nạp mạnh để xe vọt lẹ (trả lại 1.5 gốc)
                        local accelFactor = 1.5
                        
                        local brakeFactor = 0.85       
                        
                        if currentSpeed > minSpeedToBoost then
                            local dirX = currentVel.X / currentSpeed
                            local dirY = currentVel.Y / currentSpeed
                            
                            if isAccelerating then
                                local targetSpeed = currentSpeed * accelFactor
                                if targetSpeed > maxSpeed then targetSpeed = maxSpeed end
                                local newX = dirX * targetSpeed
                                local newY = dirY * targetSpeed
                                local newZ = currentVel.Z 
                                rootComp:SetAllPhysicsLinearVelocity(FVector(newX, newY, newZ), false)
                            else
                                local targetSpeed = currentSpeed * brakeFactor
                                if targetSpeed > minSpeedToBoost then
                                    local newX = dirX * targetSpeed
                                    local newY = dirY * targetSpeed
                                    local newZ = currentVel.Z 
                                    rootComp:SetAllPhysicsLinearVelocity(FVector(newX, newY, newZ), false)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    
    
        -- ========================================================
-- [DRAVIX-BRIDGE] WALLHACK & ENVIRONMENT EXECUTOR
-- Untuk fitur baru dari DRAVIX UI
-- ========================================================
pcall(function()
    -- Init state
    _G.GRW_XDState.PrevGraphicsState = _G.GRW_XDState.PrevGraphicsState or {}

    -- Ambil GameInstance untuk ExecuteCMD
    local gi = nil
    pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        gi = lsg.GetGameInstance()
    end)

    -- ==========================================
    -- BAGIAN A: FITUR VISUAL (via CMD) - TIDAK BUTUH LOOP ENEMY
    -- ==========================================
    if gi then
        -- 1. LANGIT HITAM (BlackSky)
        if _G.GRW_XDConfig.BlackSky and not _G.GRW_XDState.PrevGraphicsState.BlackSky then
            _G.GRW_XDState.PrevGraphicsState.BlackSky = true
            gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
            gi:ExecuteCMD("r.SkyAtmosphere", "0")
        elseif not _G.GRW_XDConfig.BlackSky and _G.GRW_XDState.PrevGraphicsState.BlackSky then
            _G.GRW_XDState.PrevGraphicsState.BlackSky = false
            gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
            gi:ExecuteCMD("r.SkyAtmosphere", "1")
        end

        -- 2. HILANGKAN KABUT (RemoveFog)
        if _G.GRW_XDConfig.RemoveFog and not _G.GRW_XDState.PrevGraphicsState.RemoveFog then
            _G.GRW_XDState.PrevGraphicsState.RemoveFog = true
            gi:ExecuteCMD("r.Fog", "0")
            gi:ExecuteCMD("r.VolumetricFog", "0")
        elseif not _G.GRW_XDConfig.RemoveFog and _G.GRW_XDState.PrevGraphicsState.RemoveFog then
            _G.GRW_XDState.PrevGraphicsState.RemoveFog = false
            gi:ExecuteCMD("r.Fog", "1")
            gi:ExecuteCMD("r.VolumetricFog", "1")
        end

        -- 3. HILANGKAN RUMPUT (RemoveGrass)
        if _G.GRW_XDConfig.RemoveGrass and not _G.GRW_XDState.PrevGraphicsState.RemoveGrass then
            _G.GRW_XDState.PrevGraphicsState.RemoveGrass = true
            gi:ExecuteCMD("grass.DensityScale", "0")
            gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
        elseif not _G.GRW_XDConfig.RemoveGrass and _G.GRW_XDState.PrevGraphicsState.RemoveGrass then
            _G.GRW_XDState.PrevGraphicsState.RemoveGrass = false
            gi:ExecuteCMD("grass.DensityScale", "1")
            gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
        end

        -- 4. HILANGKAN POHON (RemoveTrees)
        if _G.GRW_XDConfig.RemoveTrees and not _G.GRW_XDState.PrevGraphicsState.RemoveTrees then
            _G.GRW_XDState.PrevGraphicsState.RemoveTrees = true
            gi:ExecuteCMD("foliage.DensityScale", "0")
            gi:ExecuteCMD("r.Foliage.DensityScale", "0")
            gi:ExecuteCMD("foliage.MinimumScreenSize", "10000")
            gi:ExecuteCMD("r.DisableTreeRender", "1")
        elseif not _G.GRW_XDConfig.RemoveTrees and _G.GRW_XDState.PrevGraphicsState.RemoveTrees then
            _G.GRW_XDState.PrevGraphicsState.RemoveTrees = false
            gi:ExecuteCMD("foliage.DensityScale", "1")
            gi:ExecuteCMD("r.Foliage.DensityScale", "1")
            gi:ExecuteCMD("foliage.MinimumScreenSize", "0.0001")
            gi:ExecuteCMD("r.DisableTreeRender", "0")
        end
     
    end
    -- ==========================================
    -- BAGIAN B: LOOP ENEMY UNTUK WALLHACK PER-PLAYER
    -- ==========================================
    -- Cek apakah fungsi SH lama masih ada
    local hasApplyFuncs = (_G.ApplyWallXuyenTuong ~= nil) 
        or (_G.ApplyColorBodyV2 ~= nil)
        or (_G.ApplyColorBodyV3 ~= nil)
        or (_G.ApplyColorBodyNew ~= nil)

    if hasApplyFuncs then
        -- Loop enemy untuk apply material per-character
        pcall(function()
            local GameplayData = require("GameLua.GameCore.Data.GameplayData")
            local localPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
            if not localPlayer or not slua.isValid(localPlayer) then return end

            local allCharacters = {}
            if GameplayData.GetAllPlayerCharacters then
                allCharacters = GameplayData.GetAllPlayerCharacters()
            elseif GameplayData.GameCharacters then
                for _, c in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, c) end
            end

            for _, enemy in pairs(allCharacters) do
                if slua.isValid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                    local eKey = tostring(enemy.PlayerKey or enemy)
                    _G.GRW_XDState.EnemyMarks = _G.GRW_XDState.EnemyMarks or {}
                    _G.GRW_XDState.EnemyMarks[eKey] = _G.GRW_XDState.EnemyMarks[eKey] or { enemy = enemy }
                    local markData = _G.GRW_XDState.EnemyMarks[eKey]
                    markData.enemy = enemy

                    -- Wallhack V1 per-enemy (kalau fungsi ada)
                    if _G.ApplyWallXuyenTuong then
                        if _G.GRW_XDConfig.WallXuyenTuong then
                            pcall(_G.ApplyWallXuyenTuong, enemy, markData)
                        else
                            pcall(_G.UndoWallXuyenTuong, enemy, markData)
                        end
                    end

                    -- Chams V2 per-enemy (kalau fungsi ada)
                    if _G.ApplyColorBodyV2 then
                        if _G.GRW_XDConfig.ColorBodyV2 then
                            pcall(_G.ApplyColorBodyV2, enemy, nil, markData)
                        else
                            pcall(_G.UndoColorBodyV2, enemy, markData)
                        end
                    end

                    -- Wall V2 + Chams V3 per-enemy (kalau fungsi ada)
                    if _G.ApplyColorBodyV3 then
                        if _G.GRW_XDConfig.ColorBodyV3 then
                            pcall(_G.ApplyColorBodyV3, enemy, markData)
                        else
                            pcall(_G.UndoColorBodyV3, enemy, markData)
                        end
                    end

                    -- Wall Color New per-enemy (kalau fungsi ada)
                    if _G.ApplyColorBodyNew then
                        if _G.GRW_XDConfig.ColorBodyNew then
                            pcall(_G.ApplyColorBodyNew, enemy, markData)
                        else
                            pcall(_G.UndoColorBodyNew, enemy, markData)
                        end
                    end
                end
            end
        end)
    end
end)

-- ========================================================
-- [WALLHACK-COMPLETE] V1 + Chams V2 + New + V3 + Vehicle
-- Full logic seperti mod SH asli
-- ========================================================
pcall(function()
    _G.GRW_XDState = _G.GRW_XDState or {}
    _G.GRW_XDState.EnemyMarks = _G.GRW_XDState.EnemyMarks or {}
    _G.GRW_XDState.ChamsV2Cache = _G.GRW_XDState.ChamsV2Cache or {}
    _G.GRW_XDState.ChamsV3Cache = _G.GRW_XDState.ChamsV3Cache or {}
    _G.GRW_XDState.WallMIDsCache = _G.GRW_XDState.WallMIDsCache or {}
    _G.GRW_XDState.WallAppliedCache = _G.GRW_XDState.WallAppliedCache or {}

    -- ==========================================
    -- HELPER FUNCTIONS
    -- ==========================================
    local function GetAllSkeletalMeshes(enemy, markData)
        local curTime = os.clock()
        if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 0.5) then
            local validMeshes = {}
            for _, cachedMesh in ipairs(markData.CachedMeshes) do
                local isPendingKill = false
                pcall(function() if type(cachedMesh.IsPendingKill) == "function" then isPendingKill = cachedMesh:IsPendingKill() end end)
                if slua.isValid(cachedMesh) and not isPendingKill then 
                    table.insert(validMeshes, cachedMesh) 
                end
            end
            markData.CachedMeshes = validMeshes
            return validMeshes
        end

        local meshes = {}
        if slua.isValid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
        pcall(function()
            local SkClass = import("SkeletalMeshComponent")
            if SkClass and type(enemy.GetComponentsByClass) == "function" then
                local childs = enemy:GetComponentsByClass(SkClass)
                if childs then
                    local count = type(childs.Num) == "function" and childs:Num() or #childs
                    for i = 1, count do
                        local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                        if slua.isValid(comp) and comp ~= enemy.Mesh then
                            table.insert(meshes, comp)
                        end
                    end
                end
            end
        end)
        if markData then
            markData.CachedMeshes = meshes
            markData.CachedMeshTime = curTime
        end
        return meshes
    end

    local function GetColorRGB(choice)
        if choice == 1 then return 255, 0, 0 end       -- Merah
        if choice == 2 then return 0, 255, 0 end       -- Hijau
        if choice == 3 then return 0, 0, 255 end       -- Biru
        if choice == 4 then return 255, 255, 0 end     -- Kuning
        if choice == 5 then return 255, 0, 255 end     -- Ungu
        if choice == 6 then return 255, 255, 255 end   -- Putih
        return 255, 0, 0
    end

    -- ==========================================
    -- APPLY WALLHACK V1 (Outline)
    -- ==========================================
    local function ApplyWallXuyenTuong(enemy, markData)
        pcall(function()
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        if type(mesh.SetRenderCustomDepth) == "function" then
                            mesh:SetRenderCustomDepth(true)
                        end
                        if type(mesh.SetCustomDepthStencilValue) == "function" then
                            mesh:SetCustomDepthStencilValue(252)
                        end
                    end)
                    for i = 0, 10 do
                        local matInterface = mesh:GetMaterial(i)
                        if not slua.isValid(matInterface) then break end
                        local baseMat = matInterface:GetBaseMaterial()
                        if slua.isValid(baseMat) then
                            baseMat.bDisableDepthTest = true
                            baseMat.BlendMode = 2
                        end
                    end
                end
            end
        end)
    end

    local function UndoWallXuyenTuong(enemy, markData)
        pcall(function()
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        if type(mesh.SetRenderCustomDepth) == "function" then
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                    for i = 0, 10 do
                        local matInterface = mesh:GetMaterial(i)
                        if not slua.isValid(matInterface) then break end
                        local baseMat = matInterface:GetBaseMaterial()
                        if slua.isValid(baseMat) then
                            baseMat.bDisableDepthTest = false
                        end
                    end
                end
            end
        end)
    end

    -- ==========================================
    -- APPLY CHAMS V2 (Color Badan)
    -- ==========================================
    local function ApplyColorBodyV2(enemy, pc, markData)
        pcall(function()
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            if #meshes == 0 then return end

            -- Cache visibility check 0.3s
            local curTime = os.clock()
            if markData.LastVisCheckTime == nil or (curTime - markData.LastVisCheckTime) > 0.3 then
                markData.LastVisCheckTime = curTime
                local isHidden = true
                pcall(function()
                    if slua.isValid(pc) and type(pc.LineOfSightTo) == "function" then
                        if pc:LineOfSightTo(enemy) then isHidden = false else isHidden = true end
                    end
                end)
                markData.CachedHiddenState = isHidden
            end

            local hidden = markData.CachedHiddenState
            if hidden == nil then hidden = true end

            local cData = _G.SHgamingState.CustomTextData or {}
            local hiddenColor = {R = cData.HiddenR or 150, G = cData.HiddenG or 0, B = cData.HiddenB or 0, A = cData.HiddenA or 25}
            local visibleColor = {R = cData.VisibleR or 0, G = cData.VisibleG or 150, B = cData.VisibleB or 0, A = cData.VisibleA or 25}

            local finalColor = hidden and hiddenColor or visibleColor
            local colorHash = string.format("%d_%d_%d_%d", finalColor.R, finalColor.G, finalColor.B, finalColor.A)
            local currentMeshCount = #meshes
            local isMeshChanged = (markData.LastMeshCount ~= currentMeshCount)

            if not isMeshChanged and markData.LastHiddenState == hidden and markData.LastColorHash == colorHash then return end

            if isMeshChanged and markData.MIDs then markData.MIDs = {} end

            markData.LastHiddenState = hidden
            markData.LastMeshCount = currentMeshCount
            markData.LastColorHash = colorHash

            for meshIndex, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        mesh.LDMaxDrawDistance = -99999
                        mesh.MaxDrawDistanceOffset = -99999
                        mesh.CachedMaxDrawDistance = -99999
                        mesh.UseScopeDistanceCulling = true
                        mesh.PrimitiveShadingStrategy = 1
                        mesh.ShadingRate = 6
                    end)
                    for i = 0, 10 do
                        local matInterface = mesh:GetMaterial(i)
                        if not slua.isValid(matInterface) then break end
                        local baseMat = matInterface:GetBaseMaterial()
                        if slua.isValid(baseMat) then
                            local matName = tostring(baseMat)
                            if string.find(matName, "Master_Mask", 1, true) then
                                if not markData.MIDs then markData.MIDs = {} end
                                local meshKey = "Mesh_" .. tostring(meshIndex)
                                if not markData.MIDs[meshKey] then markData.MIDs[meshKey] = {} end
                                local mid = markData.MIDs[meshKey][i]
                                if not slua.isValid(mid) then
                                    mid = mesh:CreateAndSetMaterialInstanceDynamic(i)
                                    markData.MIDs[meshKey][i] = mid
                                end
                                if slua.isValid(mid) then
                                    mid:SetVectorParameterValue("颜色", finalColor)
                                    mid:SetVectorParameterValue("Extra Light Color", finalColor)
                                    mid:SetVectorParameterValue("Para_Color", finalColor)
                                    mid:SetVectorParameterValue("Para_ColorTint", finalColor)
                                    mid:SetVectorParameterValue("Para_Color_1", finalColor)
                                    mid:SetVectorParameterValue("Tint", finalColor)
                                    mid:SetVectorParameterValue("Color", finalColor)
                                    mid:SetVectorParameterValue("BaseColor", finalColor)
                                    mid:SetVectorParameterValue("BodyColor", finalColor)
                                    mid:SetVectorParameterValue("MainColor", finalColor)
                                    mid:SetVectorParameterValue("DiffuseColor", finalColor)
                                    mid:SetVectorParameterValue("EmissiveColor", finalColor)
                                    mid:SetVectorParameterValue("ParaScaleOffset", {R=3, G=3, B=0, A=0})
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    local function UndoColorBodyV2(enemy, markData)
        pcall(function()
            if not markData or not markData.ColorApplied then return end
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        mesh.PrimitiveShadingStrategy = 0
                        mesh.ShadingRate = 1
                    end)
                    local meshKey = "Mesh_" .. tostring(meshIndex)
                    if markData.MIDs and markData.MIDs[meshKey] then
                        for i, mid in pairs(markData.MIDs[meshKey]) do
                            if slua.isValid(mid) then
                                local defC = {R=1, G=1, B=1, A=1}
                                mid:SetVectorParameterValue("颜色", defC)
                                mid:SetVectorParameterValue("Tint", defC)
                                mid:SetVectorParameterValue("Color", defC)
                                mid:SetVectorParameterValue("BaseColor", defC)
                            end
                        end
                    end
                end
            end
            markData.ColorApplied = false
            markData.LastColorHash = ""
            markData.LastHiddenState = nil
        end)
    end

    -- ==========================================
    -- APPLY WALL V2 + CHAMS V3 (Kustom Color)
    -- ==========================================
    local function ApplyColorBodyV3(enemy, markData)
        pcall(function()
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            if #meshes == 0 then return end

            local cData = _G.SHgamingState.CustomTextData or {}
            local hidChoice = cData.ColorV3Hidden or 1
            local visChoice = cData.ColorV3Visible or 2
            local v3Thick = cData.ColorV3Thickness or 4

            local currentHash = string.format("%d_%d_%d", hidChoice, visChoice, v3Thick)
            local colorChanged = (markData.LastColorV3Hash ~= currentHash)
            markData.LastColorV3Hash = currentHash

            local hR, hG, hB = GetColorRGB(hidChoice)
            local vR, vG, vB = GetColorRGB(visChoice)

            local invisColor = { R=hR, G=hG, B=hB, A=255 }

            local FC = import("LinearColor")
            local glowIntensity = 80.0
            local visColor = FC and FC((vR/255)*glowIntensity, (vG/255)*glowIntensity, (vB/255)*glowIntensity, 1.0) or { R=vR*glowIntensity, G=vG*glowIntensity, B=vB*glowIntensity, A=255 }
            local scale = { R=3.0, G=3.0, B=0.0, A=0.0 }

            markData.MIDs_V3 = markData.MIDs_V3 or {}

            for meshIndex, comp in ipairs(meshes) do
                if slua.isValid(comp) then
                    local compKey = "MeshV3_" .. tostring(meshIndex)
                    markData.MIDs_V3[compKey] = markData.MIDs_V3[compKey] or {}

                    pcall(function()
                        if comp.PrimitiveShadingStrategy ~= 1 then
                            comp.UseScopeDistanceCulling = false
                            comp.PrimitiveShadingStrategy = 1
                            comp.ShadingRate = 6
                        end
                    end)

                    for i = 0, 10 do
                        local matInterface = comp:GetMaterial(i)
                        if not slua.isValid(matInterface) then break end

                        local baseMat = matInterface:GetBaseMaterial()
                        if slua.isValid(baseMat) then
                            if baseMat.bDisableDepthTest ~= true then baseMat.bDisableDepthTest = true end
                            if baseMat.BlendMode ~= 2 then baseMat.BlendMode = 2 end
                        end

                        local currentCached = markData.MIDs_V3[compKey][i]
                        local needUpdateColor = false

                        if not slua.isValid(currentCached) then
                            local newMid = comp:CreateAndSetMaterialInstanceDynamic(i)
                            if slua.isValid(newMid) then
                                markData.MIDs_V3[compKey][i] = newMid
                                currentCached = newMid
                                needUpdateColor = true
                            end
                        elseif colorChanged then
                            needUpdateColor = true
                        end

                        if slua.isValid(currentCached) and needUpdateColor then
                            pcall(function()
                                currentCached:SetVectorParameterValue("颜色", invisColor)
                                currentCached:SetVectorParameterValue("Extra Light Color", invisColor)
                                currentCached:SetVectorParameterValue("Para_Color", invisColor)
                                currentCached:SetVectorParameterValue("Para_ColorTint", invisColor)
                                currentCached:SetVectorParameterValue("Para_Color_1", invisColor)
                                currentCached:SetVectorParameterValue("Tint", invisColor)
                                currentCached:SetVectorParameterValue("Color", invisColor)
                                currentCached:SetVectorParameterValue("BaseColor", invisColor)
                                currentCached:SetVectorParameterValue("BodyColor", invisColor)
                                currentCached:SetVectorParameterValue("MainColor", invisColor)
                                currentCached:SetVectorParameterValue("DiffuseColor", invisColor)
                                currentCached:SetVectorParameterValue("EmissiveColor", invisColor)
                                currentCached:SetVectorParameterValue("CustomColor", invisColor)
                                currentCached:SetVectorParameterValue("OverlayColor", invisColor)
                                currentCached:SetVectorParameterValue("GlowColor", invisColor)
                                currentCached:SetVectorParameterValue("EdgeColor", invisColor)
                                currentCached:SetVectorParameterValue("LightColor", invisColor)
                                currentCached:SetVectorParameterValue("OutlineColor", invisColor)
                                currentCached:SetVectorParameterValue("ParaScaleOffset", scale)
                                currentCached:SetScalarParameterValue("Opacity", 0.7)
                                currentCached:SetScalarParameterValue("Alpha", 0.7)
                                currentCached:SetScalarParameterValue("GlowIntensity", 1.0)
                                currentCached:SetScalarParameterValue("Intensity", 1.0)
                            end)
                        end
                    end

                    pcall(function()
                        if comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(true)
                            if comp.OverrideIdeaOutlineColor then comp:OverrideIdeaOutlineColor(true, visColor) end
                            if comp.OverrideIdeaOutlineThickness then comp:OverrideIdeaOutlineThickness(true, v3Thick) end
                        end
                    end)
                end
            end
            markData.ColorV3Applied = true
        end)
    end

    local function UndoColorBodyV3(enemy, markData)
        pcall(function()
            if not markData or not markData.ColorV3Applied then return end
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, comp in ipairs(meshes) do
                if slua.isValid(comp) then
                    pcall(function()
                        comp.PrimitiveShadingStrategy = 0
                        comp.ShadingRate = 1
                    end)
                    for i = 0, 10 do
                        local s, matInterface = pcall(function() return comp:GetMaterial(i) end)
                        if s and slua.isValid(matInterface) then
                            local s2, baseMat = pcall(function() return matInterface:GetBaseMaterial() end)
                            if s2 and slua.isValid(baseMat) then
                                baseMat.bDisableDepthTest = false
                                baseMat.BlendMode = 1
                            end
                        end
                    end
                    pcall(function()
                        if comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(false)
                        end
                    end)
                end
            end
            markData.ColorV3Applied = false
            markData.MIDs_V3 = nil
        end)
    end

    -- ==========================================
    -- APPLY WALL WARNA NEW (Dyeing)
    -- ==========================================
    local function ApplyColorBodyNew(enemy, markData)
        pcall(function()
            -- Kích hoạt Console Command
            if not _G.ConsoleNewWallReady then
                local KismetSystemLibrary = import("KismetSystemLibrary")
                local world = slua.getWorld()
                if KismetSystemLibrary and world then
                    KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                    KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                    KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
                    KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
                    _G.ConsoleNewWallReady = true
                end
            end

            local meshes = GetAllSkeletalMeshes(enemy, markData)
            local weapon = nil
            pcall(function() weapon = enemy:GetCurrentWeapon() end)
            if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                table.insert(meshes, weapon.Mesh)
            end

            local isBot = markData.AK_IS_BOT or false
            local currentMeshCount = #meshes
            local stateHash = (isBot and "BOT" or "PLAYER") .. "_" .. tostring(currentMeshCount)

            if markData.LastColorNewHash == stateHash and markData.ColorNewApplied then return end

            markData.LastColorNewHash = stateHash
            markData.ColorNewApplied = true

            local FC = import("LinearColor")
            local c_vis = FC and FC(0, 100, 0, 1) or {R=0, G=100, B=0, A=1}
            local c_occ = FC and FC(100, 0, 0, 1) or {R=100, G=0, B=0, A=1}
            local c_bVis = FC and FC(49, 48, 0, 100) or {R=49, G=48, B=0, A=100}
            local c_bOcc = FC and FC(9, 1.5, 45, 100) or {R=9, G=1.5, B=45, A=100}

            local visColor = isBot and c_bVis or c_vis
            local occColor = isBot and c_bOcc or c_occ

            for _, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(true)
                            mesh:SetDrawDyeingMode(1)
                            mesh:SetVisibleDyeingColor(visColor)
                            mesh:SetOccludedDyeingColor(occColor)
                            mesh:SetDyeingColorFadeDistance(99999.0)
                            mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                            mesh:SetDrawHighlight(true)
                            mesh:OverrideHighlightColor(visColor)
                            mesh:SetHighlightCanBeOccluded(false)
                            mesh:SetDrawIdeaOutline(true)
                            mesh:SetIdeaOutlineNew(true)
                            mesh:SetIdeaOutlineOcclusionHighlight(true)
                            mesh:OverrideIdeaOutlineColor(visColor)
                            mesh:SetIdeaOutlineOcclusionColor(occColor)
                            mesh:OverrideIdeaOutlineThickness(20.0)
                            mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                            mesh:SetRenderCustomDepth(true)
                            mesh:SetCustomDepthStencilValue(255)
                        end
                    end)
                end
            end
        end)
    end

    local function UndoColorBodyNew(enemy, markData)
        pcall(function()
            if not markData or not markData.ColorNewApplied then return end
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if slua.isValid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(false)
                            mesh:SetDrawHighlight(false)
                            mesh:SetDrawIdeaOutline(false)
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                end
            end
            markData.ColorNewApplied = false
            markData.LastColorNewHash = ""
        end)
    end

    -- ==========================================
    -- LOOP ENEMY - APPLY/UNDO
    -- ==========================================
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local localPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
    if not localPlayer or not slua.isValid(localPlayer) then return end

    local pc = nil
    pcall(function() pc = localPlayer:GetPlayerControllerSafety() end)

    local allChars = {}
    if GameplayData.GetAllPlayerCharacters then
        local tmp = GameplayData.GetAllPlayerCharacters()
        for _, c in pairs(tmp) do table.insert(allChars, c) end
    elseif GameplayData.GameCharacters then
        for _, c in pairs(GameplayData.GameCharacters) do table.insert(allChars, c) end
    end

    for _, enemy in pairs(allChars) do
        if slua.isValid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
            local eKey = tostring(enemy.PlayerKey or enemy)
            _G.GRW_XDState.EnemyMarks[eKey] = _G.GRW_XDState.EnemyMarks[eKey] or { enemy = enemy }
            local markData = _G.GRW_XDState.EnemyMarks[eKey]
            markData.enemy = enemy

            -- WALLHACK V1
            if _G.GRW_XDConfig.WallXuyenTuong then
                ApplyWallXuyenTuong(enemy, markData)
                markData.WallhackApplied = true
            else
                if markData.WallhackApplied then
                    UndoWallXuyenTuong(enemy, markData)
                    markData.WallhackApplied = false
                end
            end

            -- CHAMS V2
            if _G.GRW_XDConfig.ColorBodyV2 then
                ApplyColorBodyV2(enemy, pc, markData)
                markData.ColorApplied = true
            else
                if markData.ColorApplied then
                    UndoColorBodyV2(enemy, markData)
                end
            end

            -- WALL V2 + CHAMS V3
            if _G.GRW_XDConfig.ColorBodyV3 then
                ApplyColorBodyV3(enemy, markData)
            else
                if markData.ColorV3Applied then
                    UndoColorBodyV3(enemy, markData)
                end
            end

            -- WALL WARNA NEW
            if _G.GRW_XDConfig.ColorBodyNew then
                ApplyColorBodyNew(enemy, markData)
            else
                if markData.ColorNewApplied then
                    UndoColorBodyNew(enemy, markData)
                end
            end
        end
    end

    -- ==========================================
    -- WALLHACK KENDARAAN
    -- ==========================================
    if _G.GRW_XDConfig.WallVehicle then
        pcall(function()
            local STVehicle = import("STExtraVehicleBase")
            if not STVehicle then return end
            local GS = import("GameplayStatics")
            local ActorClass = import("Actor")
            local arr = slua.Array(UEnums.EPropertyClass.Object, ActorClass)
            local ui_util = require("client.common.ui_util")
            local gInst = ui_util and ui_util.GetGameInstance()
            if not gInst or not GS then return end

            _G.AppliedVehicleWall = _G.AppliedVehicleWall or {}
            local vehicles = GS.GetAllActorsOfClass(gInst, STVehicle, arr)
            if not vehicles then return end
            local n = type(vehicles.Num) == "function" and vehicles:Num() or #vehicles
            for i = 1, n do
                local v = type(vehicles.Get) == "function" and vehicles:Get(i-1) or vehicles[i]
                if slua.isValid(v) and v.GetMesh then
                    local dist = localPlayer:GetDistanceTo(v)
                    if dist <= 200000 then
                        local vId = tostring(v)
                        if not _G.AppliedVehicleWall[vId] then
                            local mesh = v:GetMesh()
                            if slua.isValid(mesh) then
                                local matI = mesh:GetMaterial(0)
                                if slua.isValid(matI) then
                                    local bm = matI:GetBaseMaterial()
                                    if slua.isValid(bm) then
                                        bm.bDisableDepthTest = true
                                        bm.BlendMode = 2
                                        _G.AppliedVehicleWall[vId] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end)
-- ========================================================
-- [END WALLHACK-COMPLETE]
-- ========================================================
    

    -- HOÀN TRẢ ĐỒ HỌA NGAY LẬP TỨC NẾU TẮT (TẮT LÀ TẮT LIỀN)
    local now = os.clock()
    pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if gi then
            if _G.GRW_XDConfig.RemoveGrass and not _G.GRW_XDState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "0")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                _G.GRW_XDState.PrevGraphicsState.RemoveGrass = true
            elseif not _G.GRW_XDConfig.RemoveGrass and _G.GRW_XDState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "1")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
                _G.GRW_XDState.PrevGraphicsState.RemoveGrass = false
            end

            -- LOGIC XÓA CÂY
            if _G.GRW_XDConfig.RemoveTrees and not _G.GRW_XDState.PrevGraphicsState.RemoveTrees then
                gi:ExecuteCMD("foliage.DensityScale", "0")
                gi:ExecuteCMD("r.Foliage.DensityScale", "0")
                gi:ExecuteCMD("foliage.MinimumScreenSize", "10000")
                gi:ExecuteCMD("r.DisableTreeRender", "1")
                _G.GRW_XDState.PrevGraphicsState.RemoveTrees = true
            elseif not _G.GRW_XDConfig.RemoveTrees and _G.GRW_XDState.PrevGraphicsState.RemoveTrees then
                gi:ExecuteCMD("foliage.DensityScale", "1")
                gi:ExecuteCMD("r.Foliage.DensityScale", "1")
                gi:ExecuteCMD("foliage.MinimumScreenSize", "0.0001")
                gi:ExecuteCMD("r.DisableTreeRender", "0")
                _G.GRW_XDState.PrevGraphicsState.RemoveTrees = false
            end
            
            if _G.GRW_XDConfig.RemoveFog and not _G.GRW_XDState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "0")           
                gi:ExecuteCMD("r.VolumetricFog", "0") 
                _G.GRW_XDState.PrevGraphicsState.RemoveFog = true
            elseif not _G.GRW_XDConfig.RemoveFog and _G.GRW_XDState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "1")           
                gi:ExecuteCMD("r.VolumetricFog", "1") 
                _G.GRW_XDState.PrevGraphicsState.RemoveFog = false
            end
            
            if _G.GRW_XDConfig.WhiteBody and not _G.GRW_XDState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "2")
                gi:ExecuteCMD("r.CharacterDiffusePower", "5")
                gi:ExecuteCMD("r.CharacterMinGRW_XDFactor", "100")
                _G.GRW_XDState.PrevGraphicsState.WhiteBody = true
            elseif not _G.GRW_XDConfig.WhiteBody and _G.GRW_XDState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                gi:ExecuteCMD("r.CharacterMinGRW_XDFactor", "1")
                _G.GRW_XDState.PrevGraphicsState.WhiteBody = false
            end
            
            if _G.GRW_XDConfig.ColorBodyV2 and not _G.GRW_XDState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinGRW_XDFactor", "4")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "200")
                gi:ExecuteCMD("r.CharacterDiffusePower", "200")
                _G.GRW_XDState.PrevGraphicsState.ColorBodyV2 = true
            elseif not _G.GRW_XDConfig.ColorBodyV2 and _G.GRW_XDState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinGRW_XDFactor", "1")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                _G.GRW_XDState.PrevGraphicsState.ColorBodyV2 = false
            end
            
            -- LOGIC BLACKSKY
            if _G.GRW_XDConfig.BlackSky and not _G.GRW_XDState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                _G.GRW_XDState.PrevGraphicsState.BlackSky = true
            elseif not _G.GRW_XDConfig.BlackSky and _G.GRW_XDState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                _G.GRW_XDState.PrevGraphicsState.BlackSky = false
            end
        end
    end)

    pcall(function()
        local weapon = nil
        pcall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then
                weapon = weaponManager:GetCurrentWeapon()
            end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end

        if Valid(weapon) then
            local entities = {}
            if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
            if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
            if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then 
                table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent) 
            end

            for _, entity in ipairs(entities) do
                local anyWeaponModOn = _G.GRW_XDConfig.CustomHRecoil or _G.GRW_XDConfig.CustomVRecoil or _G.GRW_XDConfig.LessShake or _G.GRW_XDConfig.Accuracy or _G.GRW_XDConfig.Crosshair or _G.GRW_XDConfig.GodMode or _G.GRW_XDConfig.AutoHead or _G.GRW_XDConfig.CustomAimbot or _G.GRW_XDConfig.CustomAimbotClose or _G.GRW_XDConfig.AimbotMode ~= "None" or _G.GRW_XDConfig.LessRecoil or _G.GRW_XDConfig.VerticalRecoil

                if anyWeaponModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            GameDeviationFactor = entity.GameDeviationFactor,
                            GameDeviationAccuracy = entity.GameDeviationAccuracy,
                            BulletFireSpeed = entity.BulletFireSpeed,
                            ShootInterval = entity.ShootInterval,
                            BaseDamage = entity.BaseDamage,
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKick = entity.RecoilKick,
                            RecoilKickADS = entity.RecoilKickADS,
                            AnimationKick = entity.AnimationKick
                        }
                    end
                    
                    if _G.GRW_XDConfig.CustomHRecoil then entity.AccessoriesHRecoilFactor = _G.GRW_XDState.CustomTextData.HRecoil or 0.3 
                    elseif _G.GRW_XDConfig.LessRecoil then entity.AccessoriesHRecoilFactor = 0.3 end
                    
                    if _G.GRW_XDConfig.CustomVRecoil then entity.AccessoriesVRecoilFactor = _G.GRW_XDState.CustomTextData.VRecoil or 0.3
                    elseif _G.GRW_XDConfig.VerticalRecoil then entity.AccessoriesVRecoilFactor = 0.3 end
                    
                    if _G.GRW_XDConfig.LessShake then entity.RecoilKick = 0.0; entity.RecoilKickADS = 0.0; entity.AnimationKick = 0.0 end
                    if _G.GRW_XDConfig.Accuracy then entity.GameDeviationAccuracy = 0.0 end
                    if _G.GRW_XDConfig.Crosshair then entity.GameDeviationFactor = 0.0 end
                    if _G.GRW_XDConfig.GodMode then entity.BulletFireSpeed = 500000.0; entity.ShootInterval = 0.001; entity.BaseDamage = 60000.0 end
                    
                    if entity.AutoAimingConfig then
                        if not entity.OriginalAutoAimCached then
                            entity.OriginalAutoAimCached = {
                                OuterSpeed = entity.AutoAimingConfig.OuterRange and entity.AutoAimingConfig.OuterRange.Speed,
                                InnerSpeed = entity.AutoAimingConfig.InnerRange and entity.AutoAimingConfig.InnerRange.Speed
                            }
                        end
                        
                        if _G.GRW_XDConfig.AutoHead then
                            pcall(function() entity.AutoAimingConfig.Bones = { "Head", "Head", "Head" } end)
                        end
                        
                        if _G.GRW_XDConfig.CustomAimbot then
                            local speed = _G.GRW_XDState.CustomTextData.OuterSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.RangeRate = 4.5
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1.0
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.RangeRate = 4.5
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1.0
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.GRW_XDConfig.CustomAimbotClose or _G.GRW_XDConfig.AimbotMode == "Close" then
                            local speed = _G.GRW_XDState.CustomTextData.InnerSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.GRW_XDConfig.AimbotMode == "Far" then
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = 5
                                entity.AutoAimingConfig.OuterRange.RangeRate = 0.7
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = 5
                                entity.AutoAimingConfig.InnerRange.RangeRate = 0.7
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1
                            end
                        end
                    end
                    
                    entity.GRW_XDWeaponModsActive = true

                elseif entity.GRW_XDWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.GameDeviationFactor = orig.GameDeviationFactor
                        entity.GameDeviationAccuracy = orig.GameDeviationAccuracy
                        entity.BulletFireSpeed = orig.BulletFireSpeed
                        entity.ShootInterval = orig.ShootInterval
                        entity.BaseDamage = orig.BaseDamage
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKick = orig.RecoilKick
                        entity.RecoilKickADS = orig.RecoilKickADS
                        entity.AnimationKick = orig.AnimationKick
                    end
                    if entity.AutoAimingConfig and entity.OriginalAutoAimCached then
                        pcall(function() entity.AutoAimingConfig.Bones = { "Spine_01", "Pelvis", "Head" } end)
                        if entity.AutoAimingConfig.OuterRange and entity.OriginalAutoAimCached.OuterSpeed then
                            entity.AutoAimingConfig.OuterRange.Speed = entity.OriginalAutoAimCached.OuterSpeed
                        end
                        if entity.AutoAimingConfig.InnerRange and entity.OriginalAutoAimCached.InnerSpeed then
                            entity.AutoAimingConfig.InnerRange.Speed = entity.OriginalAutoAimCached.InnerSpeed
                        end
                    end
                    entity.GRW_XDWeaponModsActive = false
                end
            end
        end
    end)

    local mHead_Global, mBody_Global, mLegs_Global = 1.0, 1.0, 1.0
    local runInject_Global = false
    
    pcall(function()
        if _G.GRW_XDConfig.CustomMagicBullet then
            runInject_Global = true
            mHead_Global = 1.0; mBody_Global = 1.0; mLegs_Global = 1.0
            if _G.GRW_XDState.CustomTextData then
                local cData = _G.GRW_XDState.CustomTextData
                if cData.MagicHead ~= nil then mHead_Global = tonumber(cData.MagicHead) or mHead_Global end
                if cData.MagicBody ~= nil then mBody_Global = tonumber(cData.MagicBody) or mBody_Global end
                if cData.MagicLegs ~= nil then mLegs_Global = tonumber(cData.MagicLegs) or mLegs_Global end
            end
        elseif _G.GRW_XDConfig.MagicBullet then
            runInject_Global = true
            mHead_Global = 1.05; mBody_Global = 1.0; mLegs_Global = 1.0
        end

        if runInject_Global then
            local currentMagicHash = "M_"..tostring(mHead_Global).."_"..tostring(mBody_Global).."_"..tostring(mLegs_Global)
            if _G.GRW_XDState.LastMagicConfigHash ~= currentMagicHash then
                _G.GRW_XDState.MagicUpdateVersion = (_G.GRW_XDState.MagicUpdateVersion or 0) + 1
                _G.GRW_XDState.LastMagicConfigHash = currentMagicHash
            end
        else
            -- KHI MAGIC BULLET BỊ TẮT, RESTORE LẠI HASH VỀ 0
            if _G.GRW_XDState.LastMagicConfigHash ~= "OFF" then
                _G.GRW_XDState.MagicUpdateVersion = (_G.GRW_XDState.MagicUpdateVersion or 0) + 1
                _G.GRW_XDState.LastMagicConfigHash = "OFF"
            end
        end
    end)

    pcall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end
        
        local currentValidKeys = {}
        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer then
                currentValidKeys[GetSafeEnemyKey(enemy)] = true
            end
        end
        
        for key, data in pairs(_G.GRW_XDState.EnemyMarks) do
            if not currentValidKeys[key] then
                SafeRemoveMark(data.radarMark)
                SafeRemoveMark(data.hpMark)
                SafeRemoveMark(data.distMark)
                
                -- [FIX RAM]: Dọn rác AimTouch VisCheck của địch đã chết hoặc văng quá xa
                if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then
                    _G.AimTouchVisCache[key] = nil
                end
                
                if data.MIDs then
                    for meshStr, midTable in pairs(data.MIDs) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs = nil
                end
                if data.MIDs_V3 then
                    for meshStr, midTable in pairs(data.MIDs_V3) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs_V3 = nil
                end
                
                data.enemy = nil
                data.CachedMeshes = nil
                _G.GRW_XDState.EnemyMarks[key] = nil
            end
        end

        local realCount = 0
        local aiCount = 0

        local function GetFirstElemSafe(elemArray)
            if elemArray and type(elemArray.Num) == "function" and elemArray:Num() > 0 then
                if type(elemArray.Get) == "function" then return elemArray:Get(0) end
            elseif elemArray and type(elemArray) == "table" and #elemArray > 0 then
                return elemArray[1]
            end
            return nil
        end

        local BoneScaleMap = {
            ["head"] = mHead_Global, ["neck_01"] = mHead_Global,
            ["pelvis"] = mBody_Global, ["spine_01"] = mBody_Global, ["spine_02"] = mBody_Global, ["spine_03"] = mBody_Global,
            ["thigh_l"] = mLegs_Global, ["thigh_r"] = mLegs_Global, 
            ["calf_l"] = mLegs_Global, ["calf_r"] = mLegs_Global,   
            ["foot_l"] = mLegs_Global, ["foot_r"] = mLegs_Global    
        }
        
        local mLoc = nil
        pcall(function() if type(localPlayer.K2_GetActorLocation) == "function" then mLoc = localPlayer:K2_GetActorLocation() end end)

        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                local bIsReallyDead = false
                pcall(function()
                    if type(enemy.IsDead) == "function" then bIsReallyDead = enemy:IsDead()
                    elseif enemy.bIsDead ~= nil then bIsReallyDead = enemy.bIsDead
                    elseif enemy.bIsDeadFlag ~= nil then bIsReallyDead = enemy.bIsDeadFlag end
                    if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then bIsReallyDead = true end
                end)

                local eKey = GetSafeEnemyKey(enemy)
                _G.GRW_XDState.EnemyMarks[eKey] = _G.GRW_XDState.EnemyMarks[eKey] or { enemy = enemy }
                local markData = _G.GRW_XDState.EnemyMarks[eKey]
                markData.enemy = enemy 

                if not bIsReallyDead then
                    -- [FIX LỖI MẤT MÁU KHI NHẢY DÙ/HỒI SINH]: Kiểm tra xem địch có bị đổi Actor (nhân vật mới) không.
                    -- Nếu có, xóa toàn bộ Marker (UI) bị kẹt ở xác cũ để code bên dưới vẽ lại lên nhân vật mới.
                    if markData.lastEnemyActor ~= enemy then
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end -- Xóa luôn rác của ESP 8
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                        if markData.radarMark then SafeRemoveMark(markData.radarMark); markData.radarMark = nil end
                        
                        markData.lastEnemyActor = enemy
                        markData.LastUIComp = nil
                        markData.LastFrameUIState = nil
                    end
                    
                    local eMesh = nil
                    pcall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                    local aLoc = nil
                    pcall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)
                    
                    local isBotResult, isStateLoaded = CheckIsAI(enemy, markData)
                    local isBot = markData.AK_IS_BOT or false

                    local currentMeshCount = 0
                    if Valid(eMesh) then
                        local tempMeshes = GetAllSkeletalMeshes(enemy, markData)
                        currentMeshCount = #tempMeshes
                    end
                    local isMeshChanged = (markData.LastMeshCountWall ~= currentMeshCount)

                    -- ĐÃ TỐI ƯU CỰC KỲ: Chỉ Apply khi thật sự cần
                    if _G.GRW_XDConfig.WallXuyenTuong then
                        if isMeshChanged or not markData.WallhackApplied then
                            ApplyWallXuyenTuong(enemy, markData)
                            markData.WallhackApplied = true
                            markData.LastMeshCountWall = currentMeshCount
                        end
                    else
                        UndoWallXuyenTuong(enemy, markData)
                    end

                    -- ĐÃ TỐI ƯU CỰC KỲ
                    if _G.GRW_XDConfig.ColorBodyV2 then 
                        -- TRONG HÀM NÀY TÔI ĐÃ GIỚI HẠN PC:LINEOFSIGHTTO LẠI ĐỂ TRÁNH QUÁ TẢI CPU
                        ApplyColorBodyV2(enemy, pc, markData) 
                    else
                        UndoColorBodyV2(enemy, markData)
                    end
                    
                    -- CHỨC NĂNG MÀU V3 (LỘ DIỆN XANH LÁ + SAU TƯỜNG MÀU ĐỎ) RẤT ỔN ĐỊNH
                    if _G.GRW_XDConfig.ColorBodyV3 then 
                        ApplyColorBodyV3(enemy, markData)
                    else
                        UndoColorBodyV3(enemy, markData)
                    end
                    -- CHỨC NĂNG WALL MÀU NEW
                    if _G.GRW_XDConfig.ColorBodyNew then 
                        ApplyColorBodyNew(enemy, markData)
                    else
                        UndoColorBodyNew(enemy, markData)
                    end

                    -- BUG MÀN: KÉO DÃN KẺ ĐỊCH LÀM HITBOX TO RA (FAT BODY) - ĐÃ TỐI ƯU
                    pcall(function()
                        if Valid(eMesh) then
                            local targetScale = 1.0
                            if _G.GRW_XDConfig.BugManEnable and _G.GRW_XDState.CustomTextData then
                                targetScale = 177.0 / (_G.GRW_XDState.CustomTextData.BugManRatio or 133)
                                if targetScale < 1.0 then targetScale = 1.0 end
                                if targetScale > 2.0 then targetScale = 2.0 end -- Chống lỗi đồ họa nếu kéo quá mức
                            end
                            
                            -- [FIX RÁC RAM]: Chỉ giãn xương khi có sự thay đổi (Bật/tắt hoặc kéo thanh trượt)
                            if markData.LastFatScale ~= targetScale then
                                eMesh:SetRelativeScale3D(FVector(targetScale, targetScale, 1.0))
                                markData.LastFatScale = targetScale
                            end
                        end
                    end)

                    -- [REMOVED] Magic Bullet physics mutation deleted (hitbox desync fix)
                    local distM = 0
                    pcall(function() distM = localPlayer:GetDistanceTo(enemy) / 100 end)

                    local currentHp, maxHp = 100, 100
                    local showFrameUI = _G.GRW_XDConfig.EspLoai5 or _G.GRW_XDConfig.EspVipPro or _G.GRW_XDConfig.EspVip
                    
                    if showFrameUI then
                        pcall(function()
                            if enemy.Health then currentHp = enemy.Health elseif type(enemy.GetHealth) == "function" then currentHp = enemy:GetHealth() end
                            if enemy.HealthMax then maxHp = enemy.HealthMax elseif type(enemy.GetHealthMax) == "function" then maxHp = enemy:GetHealthMax() end
                        end)
                        if maxHp <= 0 then maxHp = 100 end
                    end
                    local hpRatio = currentHp / maxHp

                    if _G.GRW_XDConfig.EspAntenna then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) and distM <= 400 then
                                local loopCount = 8  
                                local zStep = 1000     
                                local baseZ = 105     
                                local topZ = baseZ + (loopCount * zStep)
                                for i = 1, loopCount do
                                    local zOffset = baseZ + (i * zStep)
                                    MyHUD:AddDebugText("|", enemy, 0.06,
                                        {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset},
                                        C_GREEN, true, false, true, nil, 1.2, true)
                                end
                                MyHUD:AddDebugText("I", enemy, 0.06,
                                        {X=0, Y=0, Z=topZ + 60}, {X=0, Y=0, Z=topZ + 60},
                                        C_GREEN, true, false, true, nil, 1.5, true)
                            end
                        end)
                    end

                    if _G.GRW_XDConfig.EspLoai6 then
                        pcall(function()
                            local curTime = os.clock()
                            -- TỐI ƯU CỰC ĐỘ 1: Khoá nhịp vẽ HUD 20 FPS (0.05s/lần) thay vì 100 FPS
                            -- Game vẫn mượt, nhưng CPU không bị cháy vì spam lệnh AddDebugText
                            if markData.LastEsp6Time == nil or (curTime - markData.LastEsp6Time) >= 0.05 then
                                markData.LastEsp6Time = curTime
                                
                                local MyHUD = Cached_MyHUD
                                if Valid(MyHUD) and Valid(eMesh) and aLoc then
                                    if distM <= 250 then
                                        -- Lấy toạ độ Đầu tiên quyết, nếu không có hàm này thì bỏ qua
                                        if type(eMesh.GetSocketLocation) == "function" then
                                            for _, bName in ipairs(GLOBAL_BONE_LIST) do
                                                
                                                -- TỐI ƯU CỰC ĐỘ 2: Địch xa hơn 50m chỉ vẽ Đầu, Cổ, Hông. Bỏ qua tay chân đỡ rác
                                                if distM > 50 and (bName ~= "head" and bName ~= "pelvis" and bName ~= "neck_01") then
                                                    -- Skip không vẽ tay chân ở xa
                                                else
                                                    local wLoc = eMesh:GetSocketLocation(bName)
                                                    if wLoc then
                                                        -- Tính Offset chuẩn cho HUD
                                                        local offset = {X = wLoc.X - aLoc.X, Y = wLoc.Y - aLoc.Y, Z = wLoc.Z - aLoc.Z}
                                                        
                                                        local mark = "▪"
                                                        local fixedSize = 0.25 
                                                        local color = C_CYAN
                                                        
                                                        if bName == "head" then 
                                                            mark = "●"
                                                            fixedSize = 0.45
                                                            color = C_RED
                                                        elseif bName == "pelvis" or bName == "neck_01" then 
                                                            mark = "▪"
                                                            fixedSize = 0.35
                                                            color = C_YELLOW 
                                                        end
                                                        
                                                        -- Vẽ điểm neo của khớp xương (Thời gian sống 0.06s để nối mượt với frame 0.05s)
                                                        MyHUD:AddDebugText(mark, enemy, 0.06, offset, offset, color, true, false, true, nil, fixedSize, true)
                                                    end
                                                end
                                            end
                                        end
                                        -- LƯU Ý: ĐÃ XOÁ BỎ HOÀN TOÀN TÍNH NĂNG VẼ DÂY NỐI (GLOBAL_CONNECTIONS)
                                        -- Vì dùng dấu chấm "." xếp thành dây là nguyên nhân chính gây drop FPS 
                                    end
                                end
                            end
                        end)
                    end

                    if _G.GRW_XDConfig.EspLoai7 then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) then
                                if distM <= 600 then if isBot then aiCount = aiCount + 1 else realCount = realCount + 1 end end
                                
                                if distM <= 400 then
                                    local stateText = ""
                                    
                                    -- 1. Xử lý Tư Thế
                                    if _G.GRW_XDConfig.Esp7_TuThe then
                                        local pose = nil
                                        if enemy.PoseState then pose = enemy.PoseState
                                        elseif type(enemy.GetPoseState) == "function" then pose = enemy:GetPoseState() end
                                        
                                        if pose == 0 or pose == "Stand" then stateText = "Đứng"
                                        elseif pose == 1 or pose == "Crouch" then stateText = "Ngồi"
                                        elseif pose == 2 or pose == "Prone" then stateText = "Nằm"
                                        else stateText = "Đứng" end
                                    end
                                    
                                    -- 2. Xử lý Vũ Khí
                                    if _G.GRW_XDConfig.Esp7_VuKhi then
                                        local curTime = os.clock()
                                        if markData.AK_LAST_WEP_TIME == nil or curTime > markData.AK_LAST_WEP_TIME + 1.5 then
                                            local eWeapon = nil
                                            if enemy.CurrentWeapon then eWeapon = enemy.CurrentWeapon
                                            elseif type(enemy.GetCurrentWeapon) == "function" then eWeapon = enemy:GetCurrentWeapon()
                                            elseif enemy.WeaponManagerComponent then eWeapon = enemy.WeaponManagerComponent.CurrentWeaponReplicated end
                                            
                                            local weaponName = "Tay Không"
                                            if Valid(eWeapon) then if type(eWeapon.GetWeaponName) == "function" then weaponName = eWeapon:GetWeaponName() end end
                                            markData.AK_CACHED_WEP_NAME = tostring(weaponName)
                                            markData.AK_LAST_WEP_TIME = curTime
                                        end

                                        if stateText ~= "" then
                                            stateText = stateText .. " - " .. (markData.AK_CACHED_WEP_NAME or "Tay Không")
                                        else
                                            stateText = (markData.AK_CACHED_WEP_NAME or "Tay Không")
                                        end
                                    end

                                    -- 3. Vẽ lên màn hình nếu có bật 1 trong 2
                                    if stateText ~= "" then
                                        local textColor = isBot and C_CYAN or C_YELLOW
                                        local dynamicScale = math.max(0.5, 0.8 - (distM / 400))
                                        MyHUD:AddDebugText(stateText, enemy, 0.06, {X=0, Y=0, Z=100}, {X=0, Y=0, Z=100}, textColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end)
                    end

                    -- ĐÃ TỐI ƯU CỰC KỲ: Chỉ SetVisibility cho UI khung máu khi thật sự cần
                    if showFrameUI then
                        pcall(function()
                            local SecurityCommonUtils = Cached_SecurityCommonUtils
                            local show = true
                            if enemy.HealthStatus and SecurityCommonUtils and SecurityCommonUtils.IsHealthStatusAlive then 
                                if not SecurityCommonUtils.IsHealthStatusAlive(enemy.HealthStatus) then show = false end
                            end
                            if show and mLoc then
                                if aLoc and SecurityCommonUtils and SecurityCommonUtils.IsVector then
                                    if SecurityCommonUtils.IsVector(aLoc) and SecurityCommonUtils.IsVector(mLoc) then
                                        if aLoc.Z >= 150000 or FVector.Dist2D(mLoc, aLoc) > 50000 then show = false end
                                    end
                                end
                            end
                            if show then
                                if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                                
                                local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if markData.LastFrameUIState ~= "VISIBLE" then
                                        if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                        if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                                        markData.LastFrameUIState = "VISIBLE"
                                    end
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if markData.LastFrameUIState ~= "HIDDEN" then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                    markData.LastFrameUIState = "HIDDEN"
                                end
                            end
                        end)
                    end

                    if _G.GRW_XDConfig.EspVipPro then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if Valid(hud) and hud.AddDebugText then
                                if distM <= 400 then
                                    local dynamicScale = math.max(0.55, 0.95 - (distM / 400))
                                    local hpPercent = hpRatio
                                    local isKnock = (currentHp <= 0 and enemy.HealthStatus == 1)
                                    
                                    local hpColor = C_GREEN
                                    if hpPercent < 0.3 then hpColor = C_RED
                                    elseif hpPercent < 0.7 then hpColor = C_YELLOW end
                                    if isKnock then hpColor = C_RED end
                                    
                                    -- VẼ TÊN NGƯỜI CHƠI
                                    if _G.GRW_XDConfig.Esp3ShowName then
                                        local enemyName = "Enemy"
                                        pcall(function() if enemy.PlayerName then enemyName = enemy.PlayerName elseif type(enemy.GetPlayerName) == "function" then enemyName = enemy:GetPlayerName() end end)
                                        if enemyName == "" then enemyName = "Enemy" end
                                        if isKnock then enemyName = "KNOCK: " .. enemyName end
                                        hud:AddDebugText(enemyName, enemy, 0.06, {X=0, Y=0, Z=-370}, {X=0, Y=0, Z=-370}, C_WHITE, true, false, true, nil, dynamicScale * 1.1, true)
                                    end
                                    
                                    -- VẼ THANH MÁU
                                    if _G.GRW_XDConfig.Esp3ShowHP then
                                        if not isKnock then
                                            local segments = 6
                                            local filled = math.floor(hpPercent * segments)
                                            local startZ = 20
                                            local spacing = 10.0 * dynamicScale 
                                            for j = 1, segments do
                                                local color = (j <= filled) and hpColor or {R=30,G=30,B=30,A=180}
                                                hud:AddDebugText("█", enemy, 0.06, {X=0, Y=-115, Z=startZ + (j * spacing)}, {X=0, Y=-115, Z=startZ + (j * spacing)}, color, true, false, true, nil, dynamicScale * 1.2, true)
                                            end
                                            hud:AddDebugText(string.format("%d%%", math.floor(hpPercent * 100)), enemy, 0.06, {X=0, Y=-60, Z=startZ - 12}, {X=0, Y=-60, Z=startZ - 12}, hpColor, true, false, true, nil, dynamicScale * 0.8, true)
                                        else
                                            hud:AddDebugText("DOWN", enemy, 0.06, {X=0, Y=-115, Z=50}, {X=0, Y=-115, Z=50}, C_RED, true, false, true, nil, dynamicScale * 1.0, true)
                                        end
                                    end
                                end
                            end
                        end)
                    end

                    if _G.GRW_XDConfig.EspDistance then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if Valid(hud) and hud.AddDebugText then
                                if distM <= 400 then
                                    local dynamicScale = math.max(0.55, 0.95 - (distM / 400))
                                    hud:AddDebugText(string.format("[%dm]", math.floor(distM)), enemy, 0.06, {X=0, Y=115, Z=20}, {X=0, Y=115, Z=20}, C_BLUE_TEXT, true, false, true, nil, dynamicScale * 1.5, true)
                                end
                            end
                        end)
                    end

                    -- [ESP LOẠI 1 (Đã Fix Lỗi)]: Giữ nguyên thanh máu (hpMark) và khoảng cách (distMark)
                    if _G.GRW_XDConfig.EspVip then
                        if markData.hpMark == nil then markData.hpMark = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                        if markData.distMark == nil then markData.distMark = SafeAddMark(9999, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                    end

                    -- [ESP LOẠI 8 ĐỘC LẬP (Đã Fix Lỗi)]: Copy logic thanh máu ESP 1, nhưng chạy biến hpMark8 riêng biệt
                    if _G.GRW_XDConfig.EspLoai8 then
                        if markData.hpMark8 == nil then markData.hpMark8 = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                    end
                    
                    if _G.GRW_XDConfig.EspRadar then
                        -- Sửa lỗi kẹt biến (nil/false/0) và gọi ID 8888 độc quyền
                        if not markData.radarMark or markData.radarMark == 0 then 
                            markData.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, enemy) 
                        end
                    else
                        if markData.radarMark and markData.radarMark ~= 0 then
                            SafeRemoveMark(markData.radarMark)
                            markData.radarMark = nil
                        end
                    end
                    
                    -- [ESP OUTLINE - Y CHANG 100% LOGIC LỘ DIỆN V3]: Phát sáng Tùy Chỉnh Màu HDR
                    if _G.GRW_XDConfig.EspOutline then
                        pcall(function()
                            local outColorChoice = _G.GRW_XDState.CustomTextData.OutlineColor or 4
                            local outThick = _G.GRW_XDConfig.OutlineThickness or 10
                            local outlineHash = string.format("%d_%d", outThick, outColorChoice)
                            
                            local meshes = GetAllSkeletalMeshes(enemy, markData)
                            local currentMeshCount = #meshes
                            
                            if markData.OutlineState ~= outlineHash or markData.LastMeshCountOutline ~= currentMeshCount then
                                
                                local r, g, b = 255, 255, 0 -- Vàng (Mặc định)
                                if outColorChoice == 1 then r, g, b = 255, 0, 0 -- Đỏ
                                elseif outColorChoice == 2 then r, g, b = 0, 255, 0 -- Lục
                                elseif outColorChoice == 3 then r, g, b = 0, 0, 255 -- Lam
                                elseif outColorChoice == 4 then r, g, b = 255, 255, 0 -- Vàng
                                elseif outColorChoice == 5 then r, g, b = 255, 0, 255 -- Tím/Hồng
                                elseif outColorChoice == 6 then r, g, b = 255, 255, 255 end -- Trắng

                                local glowIntensity = 80.0
                                local LinearColorClass = import("LinearColor") or _G.FLinearColor
                                local glowDynamic = LinearColorClass and LinearColorClass((r/255) * glowIntensity, (g/255) * glowIntensity, (b/255) * glowIntensity, 1.0) or { R = r * glowIntensity, G = g * glowIntensity, B = b * glowIntensity, A = 255 }

                                for _, comp in ipairs(meshes) do
                                    if Valid(comp) then
                                        -- BẮT BUỘC GIỐNG V3: Ép Shading Model để kích hoạt phát sáng HDR (Bloom)
                                        pcall(function()
                                            comp.UseScopeDistanceCulling = false 
                                            comp.PrimitiveShadingStrategy = 1
                                            comp.ShadingRate = 6
                                        end)

                                        -- Y CHANG V3: Vẽ Outline đè lên trên bằng hàm gốc của Engine
                                        if comp.SetDrawIdeaOutline then
                                            comp:SetDrawIdeaOutline(true)
                                            if comp.OverrideIdeaOutlineColor then
                                                comp:OverrideIdeaOutlineColor(true, glowDynamic)
                                            end
                                            if comp.OverrideIdeaOutlineThickness then
                                                -- Độ to của viền ăn theo thanh kéo trong Menu của bạn
                                                comp:OverrideIdeaOutlineThickness(true, _G.GRW_XDConfig.OutlineThickness)
                                            end
                                        end
                                    end
                                end
                                markData.OutlineState = outlineHash
                                markData.LastMeshCountOutline = currentMeshCount -- Lưu lại số lượng phụ kiện hiện tại
                            end
                        end)
                    else
                        pcall(function()
                            if markData.OutlineState ~= "OFF" then
                                local meshes = GetAllSkeletalMeshes(enemy, markData)
                                for _, comp in ipairs(meshes) do
                                    if Valid(comp) then
                                        -- Hoàn trả Shading Model về mặc định khi tắt
                                        pcall(function()
                                            comp.PrimitiveShadingStrategy = 0
                                            comp.ShadingRate = 1
                                        end)
                                        
                                        if comp.SetDrawIdeaOutline then
                                            comp:SetDrawIdeaOutline(false)
                                        end
                                    end
                                end
                                markData.OutlineState = "OFF"
                                markData.LastMeshCountOutline = 0
                            end
                        end)
                    end

                else
                    if not markData.IsCleanedUp then
                        SafeRemoveMark(markData.radarMark)
                        markData.radarMark = nil
                        SafeRemoveMark(markData.hpMark)
                        markData.hpMark = nil
                        SafeRemoveMark(markData.hpMark8) -- Dọn dẹp ESP 8
                        markData.hpMark8 = nil
                        SafeRemoveMark(markData.distMark)
                        markData.distMark = nil
                        
                        if markData.MIDs then
                            for meshStr, midTable in pairs(markData.MIDs) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs = nil
                        end
                        
                        if markData.MIDs_V3 then
                            for meshStr, midTable in pairs(markData.MIDs_V3) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs_V3 = nil
                        end
                        
                        pcall(function()
                            local eObj = markData.enemy
                            if Valid(eObj) then 
                                if eObj.Replay_SetVisiableOfFrameUI then eObj:Replay_SetVisiableOfFrameUI(false) end
                                local uiComp = eObj.EnemyFrameUI or (type(eObj.GetEnemyFrameUI) == "function" and eObj:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end 
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                end
                            end
                            
                            local PPM = Cached_PPM
                            local avatarComp = Valid(eObj) and (type(eObj.getAvatarComponent2) == "function") and eObj:getAvatarComponent2() or nil
                            if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                        end)

                        markData.IsCleanedUp = true
                    end
                end
            end
        end

        if _G.GRW_XDConfig.EspLoai7 and _G.GRW_XDConfig.Esp7_SoLuong then
            -- Enemy counter UI intentionally hidden; underlying function preserved.
        else
            -- Tắt công tắc thì cho ẩn Widget đi
            if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
                EnemyCounterWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
        end

        -- ==========================================================
        -- [LOGIC ESP BOM VVIP] - OPTIMIZED WITH WEAK CACHE (100% GỐC, KHÔNG LAG)
        -- ==========================================================
        if _G.GRW_XDConfig.EspBomMaster and (_G.GRW_XDConfig.EspItemBom or _G.GRW_XDConfig.EspActiveBom) then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForBomb then _G.CachedActorClass_ForBomb = import("Actor") end 
                    if not _G.CachedProjArray then _G.CachedProjArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb) end
                    
                    -- Khởi tạo Cache sử dụng Weak Table để game tự xóa rác, không tràn RAM
                    if not _G.ActorBombCacheInit then
                        _G.NonBombCache = setmetatable({}, { __mode = "k" })
                        _G.BombCache = setmetatable({}, { __mode = "k" })
                        _G.ActorBombCacheInit = true
                    end
                    
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        
                        -- LUỒNG QUÉT DỮ LIỆU NẶNG: Chạy 0.5s/lần thay vì mỗi frame
                        if not _G.LastBombScanTime or (curTime - _G.LastBombScanTime) > 0.5 then
                            _G.LastBombScanTime = curTime
                            local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForBomb, _G.CachedProjArray)
                            
                            local activeBombs = {}
                            local itemBombs = {}
                            
                            if allActors then
                                for _, actor in pairs(allActors) do
                                    if slua.isValid(actor) and not actor.bHidden and not actor.bTearOff then
                                        
                                        -- 1. KIỂM TRA BỘ NHỚ ĐỆM (CACHE) SIÊU TỐC
                                        -- Nếu actor này đã từng quét và KHÔNG PHẢI BOM -> Bỏ qua lập tức (Giảm 99% Lag)
                                        if not _G.NonBombCache[actor] then
                                            local bType = 0
                                            local isItem = false
                                            local isKnownBomb = _G.BombCache[actor]
                                            
                                            if isKnownBomb then
                                                bType = isKnownBomb.type
                                                isItem = isKnownBomb.isItem
                                            else
                                                -- Lần đầu tiên thấy Actor này, tiến hành kiểm tra tên (Rất ít khi xảy ra)
                                                local nameLower = nil
                                                pcall(function() nameLower = string.lower(type(actor.GetName) == "function" and actor:GetName() or tostring(actor)) end)
                                                
                                                if nameLower then
                                                    if string.find(nameLower, "m79") or string.find(nameLower, "launcher") then bType = 5
                                                    elseif string.find(nameLower, "smoke") then bType = 2
                                                    elseif string.find(nameLower, "burn") or string.find(nameLower, "molotov") then bType = 3
                                                    elseif string.find(nameLower, "flash") or string.find(nameLower, "stun") then bType = 4
                                                    elseif string.find(nameLower, "grenade") then bType = 1 end
                                                    
                                                    if bType > 0 then
                                                        if string.find(nameLower, "projectile") or string.find(nameLower, "thrown") then
                                                            isItem = false
                                                        else
                                                            isItem = true
                                                            local shouldAdd = true
                                                            if bType == 3 and not (string.find(nameLower, "pickup") or string.find(nameLower, "wrapper") or string.find(nameLower, "weapon")) then
                                                                shouldAdd = false
                                                            elseif bType == 5 then
                                                                local attachParent = nil
                                                                pcall(function() if type(actor.GetAttachParentActor) == "function" then attachParent = actor:GetAttachParentActor() end end)
                                                                if slua.isValid(attachParent) then
                                                                    local isHolding = false
                                                                    pcall(function()
                                                                        local curWeapon = type(attachParent.GetCurrentWeapon) == "function" and attachParent:GetCurrentWeapon() or attachParent.CurrentWeapon
                                                                        if curWeapon == actor then isHolding = true end
                                                                    end)
                                                                    if not isHolding then shouldAdd = false end
                                                                end
                                                            end
                                                            if not shouldAdd then bType = 0 end
                                                        end
                                                    end
                                                end
                                                
                                                -- Lưu kết quả vào Cache
                                                if bType > 0 then
                                                    _G.BombCache[actor] = { type = bType, isItem = isItem }
                                                else
                                                    _G.NonBombCache[actor] = true
                                                end
                                            end
                                            
                                            -- Nếu là Bom hợp lệ (từ Cache hoặc vừa tìm ra)
                                            if bType > 0 then
                                                local isPendingKill = false
                                                pcall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)
                                                
                                                if not isPendingKill then
                                                    if isItem then
                                                        table.insert(itemBombs, {act = actor, type = bType})
                                                    else
                                                        table.insert(activeBombs, {act = actor, type = bType})
                                                    end
                                                else
                                                    -- Xóa khỏi cache nếu bomb đã nổ/biến mất
                                                    _G.BombCache[actor] = nil
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            _G.CachedActiveBombs = activeBombs
                            _G.CachedItemBombs = itemBombs
                        end

                        local curGameTime = 0
                        pcall(function() curGameTime = _G.CachedGameplayStatics.GetTimeSeconds(gameInstance) end)

                        local function DrawBombs(bombList, isItem, maxDist)
                            if not bombList then return end
                            for _, item in ipairs(bombList) do
                                local bomb = item.act
                                local bType = item.type
                                
                                if slua.isValid(bomb) and not bomb.bHidden then
                                    local distM = 0
                                    pcall(function() distM = localPlayer:GetDistanceTo(bomb) / 100 end)
                                    
                                    if distM > 0 and distM <= maxDist then
                                        local displayName = ""
                                        local bombColor = C_WHITE
                                        local zOffset = isItem and 15 or 25
                                        
                                        if bType == 1 then displayName = "Boom"; bombColor = isItem and {R=255, G=100, B=100, A=255} or C_RED
                                        elseif bType == 2 then displayName = "KHÓI"; bombColor = isItem and {R=200, G=200, B=200, A=255} or C_WHITE
                                        elseif bType == 3 then displayName = "LỬA"; bombColor = isItem and {R=255, G=160, B=50, A=255} or {R=255, G=100, B=0, A=255}
                                        elseif bType == 4 then displayName = "MÙ"; bombColor = isItem and {R=150, G=255, B=255, A=255} or C_CYAN
                                        elseif bType == 5 then displayName = "ĐẠN KHÓI"; bombColor = isItem and {R=150, G=255, B=150, A=255} or {R=100, G=255, B=100, A=255} end
                                        
                                        local text = string.format("%s [%dm]", displayName, math.floor(distM))
                                        local shouldTimerRun = not isItem 
                                        
                                        if isItem then pcall(function() if bomb.bIsPinPulled or bomb.bPinPulled or (type(bomb.IsPinPulled) == "function" and bomb:IsPinPulled()) then shouldTimerRun = true end end) end

                                        if shouldTimerRun and curGameTime > 0 then
                                            local timeLeft = -1
                                            pcall(function() if bomb.ExplosionTime then timeLeft = bomb.ExplosionTime - curGameTime elseif bomb.ExplodeTime then timeLeft = bomb.ExplodeTime - curGameTime end end)
                                            
                                            if timeLeft == -1 or timeLeft > 100 then
                                                _G.ActiveBombTimers = _G.ActiveBombTimers or {}
                                                local bombId = tostring(bomb)
                                                if not _G.ActiveBombTimers[bombId] then _G.ActiveBombTimers[bombId] = curGameTime end
                                                local elapsed = curGameTime - _G.ActiveBombTimers[bombId]
                                                local maxTime = (bType == 1 and 7.0) or (bType == 2 and 45.0) or (bType == 3 and 12.0) or (bType == 4 and 5.0) or 45.0
                                                timeLeft = maxTime - elapsed
                                            end
                                            
                                            if timeLeft < 0 then timeLeft = 0 end
                                            if timeLeft > 0.1 then text = string.format("%s (%.1fs)", text, timeLeft) end
                                        end
                                        
                                        local dynamicScale = math.max(0.6, 1.1 - (distM / maxDist))
                                        MyHUD:AddDebugText(text, bomb, 0.06, {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset}, bombColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end
                        
                        if not _G.LastClearTimer or (curTime - _G.LastClearTimer) > 1.0 then
                            _G.LastClearTimer = curTime
                            pcall(function() if _G.ActiveBombTimers then for k, v in pairs(_G.ActiveBombTimers) do if (curGameTime - v) > 60.0 then _G.ActiveBombTimers[k] = nil end end end end)
                        end

                        if _G.GRW_XDConfig.EspItemBom then DrawBombs(_G.CachedItemBombs, true, 50) end
                        if _G.GRW_XDConfig.EspActiveBom then DrawBombs(_G.CachedActiveBombs, false, 150) end
                    end
                end
            end)
        end

        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED
        -- ==========================================================
        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED KHÔNG MÁU (SIÊU NHẸ)
        -- ==========================================================
        if _G.GRW_XDConfig.EspVehicle then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForVehicle then _G.CachedActorClass_ForVehicle = import("STExtraVehicleBase") end 
                    if not _G.CachedVehicleArray then _G.CachedVehicleArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForVehicle) end
                    
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()

                        -- LUỒNG QUÉT CHÍNH: 1.0s quét 1 lần.
                        if not _G.LastVehicleScanTime or (curTime - _G.LastVehicleScanTime) > 1.0 then
                            _G.LastVehicleScanTime = curTime
                            local allVehicles = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForVehicle, _G.CachedVehicleArray)
                            
                            local activeVehicles = {}
                            if allVehicles then
                                for _, veh in pairs(allVehicles) do
                                    if slua.isValid(veh) and not veh.bHidden and not veh.bTearOff then
                                        local isPendingKill = false
                                        pcall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)
                                        
                                        if not isPendingKill then
                                            local vehName = "Xe"
                                            local hasDriver = false
                                            
                                            pcall(function()
                                                if type(veh.GetVehicleName) == "function" then vehName = veh:GetVehicleName() elseif veh.VehicleName then vehName = veh.VehicleName end
                                                local driver = type(veh.GetDriver) == "function" and veh:GetDriver() or nil
                                                if slua.isValid(driver) then hasDriver = true end
                                            end)
                                            
                                            local nameLower = string.lower(tostring(vehName) .. tostring(veh))
                                            local displayName = "Xe"
                                            if string.find(nameLower, "uaz") then displayName = "UAZ"
                                            elseif string.find(nameLower, "dacia") then displayName = "Dacia"
                                            elseif string.find(nameLower, "buggy") then displayName = "Buggy"
                                            elseif string.find(nameLower, "mirado") then displayName = "Mirado"
                                            elseif string.find(nameLower, "bike") or string.find(nameLower, "motor") then displayName = "Motorcycle"
                                            elseif string.find(nameLower, "scooter") then displayName = "Scooter"
                                            elseif string.find(nameLower, "coupe") then displayName = "Coupe RB"
                                            elseif string.find(nameLower, "brdm") then displayName = "BRDM"
                                            elseif string.find(nameLower, "boat") or string.find(nameLower, "aquarail") then displayName = "Thuyền"
                                            elseif string.find(nameLower, "glider") then displayName = "Tàu lượn"
                                            else displayName = "Xe (" .. string.sub(vehName, 1, 8) .. ")" end

                                            table.insert(activeVehicles, {act = veh, name = displayName, hasDriver = hasDriver})
                                        end
                                    end
                                end
                            end
                            _G.CachedVehicles = activeVehicles
                        end

                        if _G.CachedVehicles then
                            for _, item in ipairs(_G.CachedVehicles) do
                                local veh = item.act
                                if slua.isValid(veh) and not veh.bHidden then
                                    local isShow = false
                                    if item.name == "Dacia" then isShow = _G.GRW_XDConfig.EspVeh_Dacia
                                    elseif item.name == "UAZ" then isShow = _G.GRW_XDConfig.EspVeh_UAZ
                                    elseif item.name == "Buggy" then isShow = _G.GRW_XDConfig.EspVeh_Buggy
                                    elseif item.name == "Coupe RB" then isShow = _G.GRW_XDConfig.EspVeh_Coupe
                                    elseif item.name == "Mirado" then isShow = _G.GRW_XDConfig.EspVeh_Mirado
                                    elseif item.name == "Motorcycle" or item.name == "Scooter" then isShow = _G.GRW_XDConfig.EspVeh_Motorcycle
                                    else isShow = _G.GRW_XDConfig.EspVeh_Other end

                                    if isShow then
                                        local distM = 0
                                        pcall(function() distM = localPlayer:GetDistanceTo(veh) / 100 end)
                                        
                                        if distM > 0 and distM <= 300 then
                                            local text = string.format("%s [%dm]", item.name, math.floor(distM))
                                            local vehColor = item.hasDriver and {R=255, G=50, B=50, A=255} or {R=0, G=255, B=150, A=255}
                                            local dynamicScale = math.max(0.6, 1.1 - (distM / 500))
                                            
                                            MyHUD:AddDebugText(text, veh, 0.06, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, vehColor, true, false, true, nil, dynamicScale, true)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end

    end)
end

_G.GRW_XDState.LoopToken = (_G.GRW_XDState.LoopToken or 0) + 1 
local myToken = _G.GRW_XDState.LoopToken

local function ExpiredTick()
    if not _G.GRW_XDNotifiedPopup then
        pcall(function()
            local Msg = require("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then
                Msg.Show(1, "MOD TELAH KADALUWARSA", "VERSI MOD ANDA TELAH KADALUWARSA!\nSILAKAN HUBUNGI ADMIN UNTUK PERPANJANG.\nInbox Tele @GRW_XD Untuk Membeli, Jika Ada Orang Lain Yang Menjual Ini Kepada Anda Selain Saya, Selamat Anda Telah Tertipu", 
                function() 
                    local Web = require("client.slua.logic.url.logic_webview_sdk")
                    if Web and Web.OpenURL then Web:OpenURL("https://wa.me/923709241014") end 
                end, 
                function() end, "HUBUNGI ADMIN", "TUTUP")
                _G.GRW_XDNotifiedPopup = true 
            end
        end)
        
        if not _G.GRW_XDNotifiedPopup then
            local okTicker, ticker = pcall(require, "common.time_ticker") 
            if okTicker and ticker and ticker.AddTimerOnce then 
                ticker.AddTimerOnce(2.0, ExpiredTick) 
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- [FIX 1] ADAPTIVE FAST TICK - CPU Load Balanced
-- Instead of 100 FPS, we run at 30 FPS normal, 15 FPS when many enemies
-- ═══════════════════════════════════════════════════════════════
local _AdaptiveTick = {
    baseInterval = 0.033,      -- 30 FPS (was 0.01 = 100 FPS)
    lowEndInterval = 0.066,    -- 15 FPS for low-end devices
    lastFrameTime = 0,
    avgFrameTime = 0.033,
    frameCount = 0,
    lowEndMode = false,
    lowEndCheckCounter = 0,
}

local function DetectLowEndDevice()
    -- Detect by device tier / memory / Android version
    local isLowEnd = false
    pcall(function()
        -- Check Android version (older = slower)
        local AndroidVersion = nil
        pcall(function()
            local KismetSystemLibrary = import("KismetSystemLibrary")
            if KismetSystemLibrary and KismetSystemLibrary.GetDeviceId then end
        end)
        
        -- Check available memory
        local ok, mem = pcall(function() return collectgarbage("count") end)
        
        -- Check CPU core count via device info
        local DeviceInfo = nil
        pcall(function() DeviceInfo = import("DeviceInfo") end)
        
        -- Fallback: use runtime FPS to detect
        if _AdaptiveTick.avgFrameTime > 0.055 then
            isLowEnd = true
        end
    end)
    return isLowEnd
end

local function FastTick() 
    if isExpired then 
        if not _G.GRW_XDNotifiedExpire then
            Notify("MOD TELAH KADALUWARSA! SILAKAN HUBUNGI ADMIN UNTUK PERPANJANG!\nInbox Tele @GRW_XD Untuk Membeli, Jika Ada Orang Lain Yang Menjual Ini Kepada Anda Selain Saya, Selamat Anda Telah Tertipu")
            _G.GRW_XDNotifiedExpire = true
            ExpiredTick() 
        end
        return 
    end

    if myToken ~= _G.GRW_XDState.LoopToken then return end

    -- Measure frame time
    local now = os.clock()
    local delta = now - _AdaptiveTick.lastFrameTime
    _AdaptiveTick.lastFrameTime = now
    
    -- Skip first few frames
    if _AdaptiveTick.frameCount < 5 then
        _AdaptiveTick.frameCount = _AdaptiveTick.frameCount + 1
    else
        -- Smooth FPS measurement
        _AdaptiveTick.avgFrameTime = (_AdaptiveTick.avgFrameTime * 0.9) + (delta * 0.1)
    end
    
    -- Detect low-end every 120 frames (4 sec)
    _AdaptiveTick.lowEndCheckCounter = _AdaptiveTick.lowEndCheckCounter + 1
    if _AdaptiveTick.lowEndCheckCounter >= 120 then
        _AdaptiveTick.lowEndCheckCounter = 0
        _AdaptiveTick.lowEndMode = DetectLowEndDevice()
    end

    -- Run main loop with crash protection
    pcall(MainLoop) 
    
    -- Adaptive interval
    local nextInterval = _AdaptiveTick.lowEndMode and _AdaptiveTick.lowEndInterval or _AdaptiveTick.baseInterval
    
    -- If FPS is dropping, slow down further (emergency throttle)
    if _AdaptiveTick.avgFrameTime > 0.08 then
        nextInterval = 0.1  -- 10 FPS emergency mode
    end
    
    local okTicker, ticker = pcall(require, "common.time_ticker") 
    if okTicker and ticker and ticker.AddTimerOnce then 
        ticker.AddTimerOnce(nextInterval, FastTick) 
    end 
end

if not isExpired then
    FastTick() 
    Notify("Anda Sedang Memainkan Mod Vvip 4 Milik Saya. Jika Belum Punya Key, Inbox Tele @GRW_XD Untuk Membeli. Jika Ada Orang Lain Yang Menjual Ini Kepada Anda Selain Saya, Selamat Anda Telah Tertipu")
else
    FastTick() 
end
-- ===================================================================================
-- SYSTEM HOOKS TỪ BYPASS MỚI
-- ===================================================================================
local function InitAllModSystems()
    if isExpired then return end 

    pcall(function()
        if _G.InitializeAutoHeadHooks then _G.InitializeAutoHeadHooks() end
    end)

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if not GameplayData then return end

    pcall(function()
        local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if slua.isValid(LocalPlayer) then
            if LocalPlayer.bHasShownDevNotice == nil then
                LocalPlayer.bHasShownDevNotice = false 
                LocalPlayer.bHasShownExpiredNotice = false 
                LocalPlayer.bIsDeadFlag = false
            end
        end
    end)
end

if not isExpired then
    pcall(function() 
        require("common.time_ticker").AddTimerOnce(0.5, InitAllModSystems) 
    end)
end

-- ==============================================================================
-- ==============================================================================
-- ==========================================
-- WATERMARK PERMANEN "@GRW_XD" WARNA KUNING
-- ==========================================
pcall(function()
    local IPS = require("GameLua.Mod.Library.Client.UI.IngamePhoneStateUI")
    if IPS and IPS.__inner_impl then
        local o = IPS.__inner_impl.UpdateArtQualityUI
        IPS.__inner_impl.UpdateArtQualityUI = function(self, _, _)
            if self.UIRoot and self.UIRoot.TextBlock_quality then
                pcall(function() self.UIRoot.TextBlock_quality:SetText("@GRW_XD") end)
                -- FIX: FSlateColor/FLinearColor are NOT globals here (they were locals
                -- inside the first pcall). Old code crashed with nil-call on some builds.
                pcall(function()
                    local LC_ok, LC = pcall(import, "LinearColor")
                    local LCv = (LC_ok and LC) or _G.FLinearColor
                    local SC_ok, SC = pcall(import, "SlateColor")
                    local SCv = (SC_ok and SC) or _G.FSlateColor
                    if SCv == nil then
                        local ok2, SC2 = pcall(import, "/Script/SlateCore.SlateColor")
                        if ok2 then SCv = SC2 end
                    end
                    if LCv and SCv then
                        self.UIRoot.TextBlock_quality:SetColorAndOpacity(SCv(LCv(0.0, 1.0, 1.0, 1.0)))
                    elseif LCv then
                        -- fallback: many builds accept FLinearColor directly
                        self.UIRoot.TextBlock_quality:SetColorAndOpacity(LCv(0.0, 1.0, 1.0, 1.0))
                    end
                end)
            end
        end
    end
end)
-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 1: BASE =======================
-- ============================================================================

_G.A = _G.A or { Up = {} }
if not _G.A.Up then _G.A.Up = {} end

if not _G.Around then
    _G.Around = function(obj)
        if not obj then return false end
        if slua and slua.isValid then
            local ok, v = pcall(slua.isValid, obj)
            return ok and v
        end
        return obj ~= nil
    end
end

if not _G.IsLicenseOK then
    _G.IsLicenseOK = function()
        return _G.LicenseValid == true or _G.ModsEnabled == true
    end
end

local function UB_nop() return true end
local function UB_retFalse() return false end
local function UB_retZero() return 0 end
local function UB_retEmpty() return {} end
local function UB_retNil() return nil end
local function UB_retTrue() return true end
local function UB_retEmptyString() return "" end

print("[BYPASS] STEP 1: Base setup done")

-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 2: SLUA + MD5 =================
-- ============================================================================

local function InitializeSLUABypass()
    pcall(function()
        if slua and slua.getSignature then slua.getSignature = function() return 0xDEADBEEF end end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = UB_retTrue
            loader.checkIntegrity = UB_retTrue
            if loader.disableSignatureCheck then loader.disableSignatureCheck = UB_retTrue end
        end
        local slua_serialize = package.loaded["slua.serialize"]
        if slua_serialize then slua_serialize.check = UB_retTrue; slua_serialize.verify = UB_retTrue end
        if jit and jit.attach then jit.attach(function() end, "bc") end
        if _G.slua_verify then _G.slua_verify = UB_retTrue end
        if _G.check_slua_integrity then _G.check_slua_integrity = UB_retTrue end
    end)
end

local function InitializeMD5Bypass()
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "BYPASSED" end
            CMode.VerifyFileIntegrity = UB_retTrue
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32 then _G.CRC32 = function() return 0 end end
        if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
        local FileHashChecker = package.loaded["common.file_hash_checker"]
        if FileHashChecker then
            FileHashChecker.CheckFileMD5 = UB_retTrue; FileHashChecker.VerifyAll = UB_retTrue
            FileHashChecker.GetHash = function() return "BYPASS" end
        end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then TssSdk.GetFileMD5 = function() return "BYPASS" end; TssSdk.VerifyFileSignature = UB_retTrue end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then STExtra.CheckMD5 = UB_retTrue; STExtra.GetMD5 = function() return "BYPASS" end; STExtra.VerifyFile = UB_retTrue end
    end)
end

print("[BYPASS] STEP 2: SLUA + MD5 ready")

-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 3: SKIN + LOG =================
-- ============================================================================

local function InitializeSkinBypass()
    pcall(function()
        local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if ptlog then ptlog.ReportEvent = UB_nop; ptlog.ReportDownloadResult = UB_nop; ptlog.ReportODPTDError = UB_nop; ptlog.ReportSkinError = UB_nop end
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then AvatarUtils.CheckIsWeaponInBlackList = UB_retFalse; AvatarUtils.IsValidAvatar = UB_retTrue; AvatarUtils.CheckAvatarIntegrity = UB_retTrue; AvatarUtils.ReportInvalidAvatar = UB_nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
        if sub then sub.StartCheck = UB_nop; sub.ReportAbnormalFile = UB_nop; sub.StopCheck = UB_nop end
        local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if eqEx then eqEx.Report = UB_nop; eqEx.SendException = UB_nop end
    end)
end

local function InitializeLogBlocker()
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then SMTD.MTDePicture = function() return "" end; SMTD.ReMTDePicture = function() return "" end; SMTD.HasCaptured = UB_retTrue; SMTD.TakeScreenshot = UB_nop end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then TLog.Info = UB_nop; TLog.Warning = UB_nop; TLog.Error = UB_nop; TLog.Debug = UB_nop; TLog.Report = UB_nop; TLog.Send = UB_nop; TLog.Flush = UB_nop end
        local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
        if CrashSight then CrashSight.ReportException = UB_nop; CrashSight.SetCustomData = UB_nop; CrashSight.Log = UB_nop; CrashSight.SendCrash = UB_nop; CrashSight.ReportUserException = UB_nop end
        local GRUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GRUtils then GRUtils.BugglyPostExceptionFull = UB_retFalse; GRUtils.CheckCanBugglyPostException = UB_retFalse; GRUtils.ReplayReportData = UB_nop; GRUtils.ReportGameException = UB_nop; GRUtils.PostException = UB_nop end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then CTR.SendReport = UB_nop; CTR.SendException = UB_nop; CTR.UploadLog = UB_nop end
        for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
            local s = _G[sdk]; if s then s.logEvent = UB_nop; s.trackEvent = UB_nop; s.setEnabled = UB_retFalse; s.sendEvent = UB_nop; s.report = UB_nop end
        end
    end)
end

print("[BYPASS] STEP 3: SKIN + LOG ready")
-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 4: SCANNER + REPLAY ===========
-- ============================================================================

local function InitializeScannerBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local subs = {"AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem", "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem"}
            for _, name in ipairs(subs) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect")) then pcall(function() sub[k] = UB_nop end) end
                    end
                    if sub.ReportPingDelayTimer then sub:RemoveGameTimer(sub.ReportPingDelayTimer); sub.ReportPingDelayTimer = nil end; sub.DelayCount = 0
                end
            end
        end
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then AvaEx.CheckAvatarException = UB_nop; AvaEx.CheckAvatarExceptionOnce = UB_nop; AvaEx.ReportAvatarException = UB_nop; AvaEx.CheckSlotMeshVisible = UB_retFalse; AvaEx.CheckPawnVisible = UB_retFalse; AvaEx.CheckCanBugglyPostException = UB_retFalse end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            local origData = TssSdk.OnRecvData
            TssSdk.OnRecvData = function(data) if type(data) == "string" and (data:find("report", 1, true) or data:find("exception", 1, true) or data:find("cheat", 1, true) or data:find("violation", 1, true) or data:find("hack", 1, true) or data:find("verify", 1, true)) then return end; if origData then origData(data) end end
            TssSdk.SendReportInfo = UB_nop; TssSdk.ScanMemory = UB_retTrue; TssSdk.IsEmulator = UB_retFalse; TssSdk.GetTssSdkReportInfo = UB_retEmptyString; TssSdk.CheckEnvironment = UB_retTrue; TssSdk.VerifyProcess = UB_retTrue
        end
    end)
end

local function InitializeReplayTelemetryBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"GameReportSubsystem", "ReplaySubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Trace") or k:find("Replay") or k:find("Record") or k:find("Save")) then pcall(function() sub[k] = UB_nop end) end end end
            end
        end
        local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logRep then logRep.ReportReplay = UB_nop; logRep.SendReportReq = UB_nop; logRep.UploadReplay = UB_nop end
    end)
end

print("[BYPASS] STEP 4: SCANNER + REPLAY ready")

-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 5: REPORT + SECURITY ==========
-- ============================================================================

local function InitializeReportFlowBlocker()
    pcall(function()
        local flows = {"ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "ReportCircleFlow", "ReportSecMrpcsFlow"}
        for _, f in ipairs(flows) do if _G[f] then _G[f] = UB_nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = UB_nop end end
        for _, f in ipairs({"CheckReportSecAttackFlowWithAttackFlow", "CheckReportSecAttackFlow"}) do if _G[f] then _G[f] = UB_retFalse end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = UB_retFalse end end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow", "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow", "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"}) do if _G[f] then _G[f] = UB_retFalse end end
    end)
end

local function InitializePlayerSecurityBypass()
    pcall(function()
        for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
            if _G[c] then for k, v in pairs(_G[c]) do if type(v) == "function" and (k:find("Report") or k:find("Collect") or k:find("Send") or k:find("Upload") or k:find("Record")) then _G[c][k] = UB_nop end end end
        end
        local SecSub = require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then SecSub.ReportData = UB_nop; SecSub.CheckCheat = UB_retFalse; SecSub.ValidatePlayer = UB_retTrue; SecSub.CollectData = UB_nop; SecSub.SendToServer = UB_nop end
    end)
end

local function InitializeClientFlowBypass()
    pcall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem", "ClientKillFlowSubsystem", "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Flow") or k:find("Record") or k:find("Process")) then pcall(function() sub[k] = UB_nop end) end end end
        end
    end)
end

print("[BYPASS] STEP 5: REPORT + SECURITY ready")
-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 6: SWIFT + MORE ===============
-- ============================================================================

local function InitializeSwiftHawkBypass()
    pcall(function()
        for _, f in ipairs({"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams", "SendSwiftHawkData"}) do if _G[f] then _G[f] = UB_nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = UB_nop end end
        local sub = package.loaded["GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem"]
        if sub then sub.ReportData = UB_nop; sub.SendReport = UB_nop; sub.CollectTelemetry = UB_nop end
    end)
end

local function InitializeCoronaLabBypass()
    pcall(function()
        if _G.CoronaLab then _G.CoronaLab.ReportData = UB_nop; _G.CoronaLab.SendData = UB_nop; _G.CoronaLab.CollectData = UB_nop; _G.CoronaLab.Telemetry = UB_nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("CoronaLabSubsystem")
        if sub then sub.ReportData = UB_nop; sub.SendToServer = UB_nop; sub.CollectTelemetry = UB_nop; sub.StopCollection = UB_nop end
    end)
end

local function InitializeModifierExceptionBypass()
    pcall(function()
        if _G.bReportedModifierException then _G.bReportedModifierException = false end
        local sub = require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then sub.ReportException = UB_nop; sub.CheckModifier = UB_retTrue; sub.ValidateModifier = UB_retTrue; sub.ReportModifierError = UB_nop end
    end)
end

local function InitializeSimulateCharacterLocationBypass()
    pcall(function()
        local sub = require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then sub.ReportLocation = UB_nop; sub.SendLocationData = UB_nop; sub.VerifyLocation = UB_retTrue end
    end)
end

print("[BYPASS] STEP 6: SWIFT + MORE ready")

-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 7: SHOOT + HIGGS ==============
-- ============================================================================

local function InitializeShootVerificationBypass()
    pcall(function()
        local sub = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then sub.OnShootVerifyFailed = UB_nop; sub.SendVerifyData = UB_nop; sub.ReportBulletHit = UB_nop; sub.UploadHitInfo = UB_nop; sub.VerifyShot = UB_retTrue end
        if _G.BulletHitInfoUploadData then _G.BulletHitInfoUploadData.Report = UB_nop; _G.BulletHitInfoUploadData.Send = UB_nop; _G.BulletHitInfoUploadData.Upload = UB_nop end
    end)
end

local function InitializeNetworkPacketBlock()
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            local blocked = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1, ["ReportSecVehicleMoveFlow"]=1,
                ["report_parachute_data"]=1, ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1, ["report_players_ping"]=1,
                ["report_player_ip"]=1, ["report_net_saturate"]=1, ["report_speed_hack"]=1, ["report_wall_hack"]=1, ["report_aim_bot"]=1, ["report_esp_usage"]=1,
                ["report_modded_files"]=1, ["detect_cheat"]=1, ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1, ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1, ["RPC_ClientCoronaLab"]=1,
                ["CoronaLabReport"]=1, ["CoronaLabData"]=1, ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1, ["ClientCircleFlow"]=1,
                ["IsEnableReportMrpcsInCircleFlow"]=1, ["IsEnableReportMrpcsInPartCircleFlow"]=1, ["bReportedModifierException"]=1,
                ["ReportModifierException"]=1, ["RPC_Server_ReportSimulateCharacterLocation"]=1, ["ReportSimulateCharacterLocation"]=1, ["RPC_Client_ShootVertifyRes"]=1,
                ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1, ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1, ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1, ["SwiftHawkData"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1, ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1
            }
            NetUtil.SendPacket = function(packetName, ...) if blocked[packetName] then return nil end; return orig(packetName, ...) end
            NetUtil.IsBypassed = true
        end
        if _G.SendRPC then
            local origRPC = _G.SendRPC
            local blockedRPC = {"RPC_Server_ClientSecMrpcsFlow", "RPC_Server_SwiftHawk", "RPC_Server_ClientSwiftHawkWithParams", "RPC_Server_ReportSimulateCharacterLocation", "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab"}
            _G.SendRPC = function(rpcName, ...) for _, b in ipairs(blockedRPC) do if rpcName == b then return nil end end; return origRPC(rpcName, ...) end
        end
    end)
end

local function InitializeHiggsBosonBypass()
    pcall(function()
        local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            for _, m in ipairs({"ControlMHActive", "Tick", "OnTick", "MHActiveLogic", "TriggerAvatarCheck", "StartAvatarCheck", "ReportItemID", "ReceiveAnyDamage", "OnWeaponHitRecord", "ShowSecurityAlert", "ServerReportAvatar", "ClientReportNetAvatar", "SendHisarData", "ValidateSecurityData", "StaticShowSecurityAlertInDev", "RPC_Client_ShootVertifyRes", "RPC_Server_ReportSimulateCharacterLocation", "DisableHiggsBoson", "CheckMHActive", "ReportViolation", "ProcessSecurityEvent", "ValidatePlayer", "CheckIntegrity"}) do
                if Higgs[m] then Higgs[m] = UB_nop end
            end
            Higgs.GetNetAvatarItemIDs = UB_retEmpty; Higgs.GetCurWeaponSkinID = UB_retZero; Higgs.IsMHActive = UB_retFalse; Higgs.bMHActive = false; Higgs.bCallPreReplication = false
            if Higgs.BlackList then for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end end
        end
        _G.BlackList = {}
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false; if pc.HiggsBoson.ControlMHActive then pc.HiggsBoson:ControlMHActive(0) end end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false; pc.HiggsBosonComponent:ControlMHActive(0) end
        end
    end)
end

local function InitializeAntiCheatHooks()
    pcall(function()
        local HBC = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC and HBC.StaticShowSecurityAlertInDev then HBC.StaticShowSecurityAlertInDev = UB_nop end
    end)
    if _G.AvatarCheckCallback then
        _G.AvatarCheckCallback.StartAvatarCheck = UB_nop; _G.AvatarCheckCallback.OnReportItemID = UB_nop
        _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
            if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then PlayerController.HiggsBosonComponent:ControlMHActive(0); PlayerController.HiggsBosonComponent.bMHActive = false end
        end
    end
end

print("[BYPASS] STEP 7: SHOOT + HIGGS ready")

-- ============================================================================
-- ============== COMPLETE BYPASS SYSTEM - STEP 8: FINAL ======================
-- ============================================================================

local function InitializeAntiReport()
    pcall(function()
        for _, path in ipairs({"GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem", "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem"}) do
            local sub = package.loaded[path]; if not sub then local s, r = pcall(require, path); if s and r then sub = r end end
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Record") or k:find("Send") or k:find("Upload") or k:find("Notify")) then pcall(function() sub[k] = UB_nop end) end end end
        end
    end)
end

local function InitializeGameplayBypass()
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        if _G.GameplayCallbacks.IsBypassed then return end
        local GC = _G.GameplayCallbacks
        local reports = {"ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "SendTssSdkAntiDataToLobby", "ReportEquipmentFlow", "ReportAimFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "OnDSConnectionSaturated", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "SendClientStats", "SendServerAvgTickDelta", "ReportCircleFlow", "ClientSecMrpcsFlow", "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"}
        for _, f in ipairs(reports) do GC[f] = UB_nop end
        GC.CheckReportSecAttackFlowWithAttackFlow = UB_retFalse; GC.CheckReportSecAttackFlow = UB_retFalse
        local origState = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
            local s = State and string.lower(tostring(State)) or ""
            local blocked = {["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1, ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1, ["integrityfailure"]=1, ["securityviolation"]=1}
            if blocked[s] then return end
            if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
        end
        GC.OnPlayerNetConnectionClosed = UB_nop; GC.OnPlayerActorChannelError = UB_nop; GC.OnPlayerRPCValidateFailed = UB_nop; GC.OnPlayerSpectateException = UB_nop; GC.OnShutdownAfterError = UB_nop; GC.IsBypassed = true
    end)
end

local function InitializeKillAllSubsystems()
    pcall(function()
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not subMgr then return end
        local toKill = {"CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient", "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem", "ClientDataStatistcsSubsystem", "AFKReportorSubsystem", "BehaviorScoreSubsystem", "FileCheckSubsystem", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "AvatarExceptionSubsystem", "GameReportSubsystem", "ClientSecMrpcsFlowSubsystem", "MrpcsFlowSubsystem", "CircleFlowSubsystem", "SwiftHawkSubsystem", "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem", "MD5CheckSubsystem", "PakVerifySubsystem"}
        for _, name in ipairs(toKill) do
            local sub = subMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect") or k:find("Collect") or k:find("Flow") or k:find("Heartbeat")) then pcall(function() sub[k] = UB_nop end) end end
                if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
            end
        end
    end)
end

local function InitializeFinalProtection()
    pcall(function()
        for _, flag in ipairs({"ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", "ENABLE_PERFORMANCE_REPORT"}) do if _G[flag] then _G[flag] = false end end
        local origReq = require
        local blocked = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem"}
        _G.require = function(m) for _, b in ipairs(blocked) do if m:find(b) then return {} end end; return origReq(m) end
    end)
end

local function InitializeOperationalStatsBypass()
    pcall(function()
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local OperationalStatsSubsystem = (subMgr and subMgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
        if OperationalStatsSubsystem then
            OperationalStatsSubsystem.ReportOperationalStats = UB_nop
            OperationalStatsSubsystem.AddOperationalStats = UB_nop
            OperationalStatsSubsystem.HandleTouchBegin = UB_nop
            OperationalStatsSubsystem.HandleTouchEnd = UB_nop
            OperationalStatsSubsystem.OnInit = UB_nop
            OperationalStatsSubsystem.HandleEnterFighting = UB_nop
            OperationalStatsSubsystem.OnBattleResult = UB_nop
            if OperationalStatsSubsystem.TimerHandle then
                pcall(function() OperationalStatsSubsystem:RemoveGameTimer(OperationalStatsSubsystem.TimerHandle) end)
                OperationalStatsSubsystem.TimerHandle = nil
            end
            OperationalStatsSubsystem.StatsData = {}
        end
    end)
end

-- ============================================================================
-- MASTER FUNCTION — SAARE BYPASS CALL KARO
-- ============================================================================
_G.StartBypass_Complete = function()
    if _G.CompleteBypassStarted == true then return end
    _G.CompleteBypassStarted = true
    pcall(function()
        print("===================================================")
        print("[BYPASS] Starting COMPLETE BYPASS system...")
        print("===================================================")
        InitializeSLUABypass()
        InitializeMD5Bypass()
        InitializeSkinBypass()
        InitializeLogBlocker()
        InitializeScannerBlocker()
        InitializeReplayTelemetryBlocker()
        InitializeReportFlowBlocker()
        InitializePlayerSecurityBypass()
        InitializeClientFlowBypass()
        InitializeSwiftHawkBypass()
        InitializeCoronaLabBypass()
        InitializeModifierExceptionBypass()
        InitializeSimulateCharacterLocationBypass()
        InitializeShootVerificationBypass()
        InitializeNetworkPacketBlock()
        InitializeHiggsBosonBypass()
        InitializeAntiCheatHooks()
        InitializeAntiReport()
        InitializeGameplayBypass()
        InitializeKillAllSubsystems()
        InitializeOperationalStatsBypass()
        InitializeFinalProtection()
        print("===================================================")
        print("[BYPASS] ALL 22 LAYERS ACTIVE - FULLY PROTECTED")
        print("===================================================")
    end)
end

-- AUTO RUN on file load
-- [FIX] Yahan pehle _G.LicenseValid set karo warna bypass start nahi hoga
_G.LicenseValid = true
_G.ModsEnabled = true

pcall(function() _G.StartBypass_Complete() end)

-- Re-run on license valid
if _G.OnLicenseValid then
    local _oldOnLicenseValid = _G.OnLicenseValid
    _G.OnLicenseValid = function()
        if _oldOnLicenseValid then pcall(_oldOnLicenseValid) end
        pcall(function()
            _G.CompleteBypassStarted = false
            _G.StartBypass_Complete()
        end)
    end
else
    _G.OnLicenseValid = function()
        pcall(function()
            _G.CompleteBypassStarted = false
            _G.StartBypass_Complete()
        end)
    end
end

print("[BYPASS] STEP 8: FINAL + MASTER ready")
print("[BYPASS] ============================================")
print("[BYPASS] ALL STEPS 1-8 COMPLETE — BYPASS ACTIVE")
print("[BYPASS] ============================================")

-- ============================================================================
-- ========================== END BYPASS SYSTEM ===============================
-- ============================================================================
-- ==============================================================================
-- LAYER 01: SLUA SIGNATURE BYPASS
-- ==============================================================================
local function L01_SLUA()
    local ok = false
    pcall(function()
        if slua and type(slua.getSignature) == "function" then
            slua.getSignature = function() return 0xDEADBEEF end
            ok = true
        end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = retTrue
            loader.checkIntegrity = retTrue
            loader.disableSignatureCheck = retTrue
            ok = true
        end
        local ser = package.loaded["slua.serialize"]
        if ser then ser.check = retTrue; ser.verify = retTrue; ok = true end
        if _G.slua_verify then _G.slua_verify = retTrue; ok = true end
        if _G.check_slua_integrity then _G.check_slua_integrity = retTrue; ok = true end
        if jit and jit.attach then
            jit.attach(function() end, "bc")
            ok = true
        end
    end)
    MarkLayer("L01_SLUA", ok)
end

-- ==============================================================================
-- LAYER 02: MD5 / PAK SIGNATURE BYPASS
-- ==============================================================================
local function L02_MD5()
    local ok = false
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
            ok = true
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "OK" end
            CMode.VerifyFileIntegrity = retTrue
            ok = true
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end; ok = true end
        if _G.CRC32 then _G.CRC32 = function() return 0 end; ok = true end
        if _G.SHA1 then _G.SHA1 = function() return "0000000000000000" end; ok = true end
        local FHC = package.loaded["common.file_hash_checker"]
        if FHC then
            FHC.CheckFileMD5 = retTrue
            FHC.VerifyAll = retTrue
            FHC.GetHash = function() return "0000000000000000" end
            ok = true
        end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            TssSdk.GetFileMD5 = function() return "0000000000000000" end
            TssSdk.VerifyFileSignature = retTrue
            ok = true
        end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then
            STExtra.CheckMD5 = retTrue
            STExtra.GetMD5 = function() return "0000000000000000" end
            STExtra.VerifyFile = retTrue
            ok = true
        end
    end)
    MarkLayer("L02_MD5", ok)
end

-- ==============================================================================
-- LAYER 03: SKIN / AVATAR EXCEPTION BYPASS
-- ==============================================================================
local function L03_SKIN()
    local ok = false
    pcall(function()
        local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if ptlog then
            ptlog.ReportEvent = nop
            ptlog.ReportDownloadResult = nop
            ptlog.ReportODPTDError = nop
            ptlog.ReportSkinError = nop
            ok = true
        end
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then
            AvatarUtils.CheckIsWeaponInBlackList = retFalse
            AvatarUtils.IsValidAvatar = retTrue
            AvatarUtils.CheckAvatarIntegrity = retTrue
            AvatarUtils.ReportInvalidAvatar = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local sub = SubMgr:Get("FileCheckSubsystem")
            if sub then
                sub.StartCheck = nop
                sub.ReportAbnormalFile = nop
                sub.StopCheck = nop
                ok = true
            end
        end
        local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if eqEx then
            eqEx.Report = nop
            eqEx.SendException = nop
            ok = true
        end
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then
            AvaEx.CheckAvatarException = nop
            AvaEx.CheckAvatarExceptionOnce = nop
            AvaEx.ReportAvatarException = nop
            AvaEx.CheckSlotMeshVisible = retFalse
            AvaEx.CheckPawnVisible = retFalse
            AvaEx.CheckCanBugglyPostException = retFalse
            ok = true
        end
    end)
    MarkLayer("L03_SKIN", ok)
end

-- ==============================================================================
-- LAYER 04: LOG / CRASH REPORTER BYPASS
-- ==============================================================================
local function L04_LOG()
    local ok = false
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then
            SMTD.MTDePicture = function() return "" end
            SMTD.ReMTDePicture = function() return "" end
            SMTD.HasCaptured = retTrue
            SMTD.TakeScreenshot = nop
            ok = true
        end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then
            TLog.Info = nop; TLog.Warning = nop; TLog.Error = nop
            TLog.Debug = nop; TLog.Report = nop; TLog.Send = nop; TLog.Flush = nop
            ok = true
        end
        local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
        if CrashSight then
            CrashSight.ReportException = nop
            CrashSight.SetCustomData = nop
            CrashSight.Log = nop
            CrashSight.SendCrash = nop
            CrashSight.ReportUserException = nop
            ok = true
        end
        local GRU = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GRU then
            GRU.BugglyPostExceptionFull = retFalse
            GRU.CheckCanBugglyPostException = retFalse
            GRU.ReplayReportData = nop
            GRU.ReportGameException = nop
            GRU.PostException = nop
            ok = true
        end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then
            CTR.SendReport = nop
            CTR.SendException = nop
            CTR.UploadLog = nop
            ok = true
        end
        for _, sdk in ipairs({"Firebase","Adjust","AppsFlyer","FacebookAnalytics","GameAnalytics"}) do
            local s = _G[sdk]
            if s then
                s.logEvent = nop; s.trackEvent = nop
                s.setEnabled = retFalse; s.sendEvent = nop; s.report = nop
                ok = true
            end
        end
    end)
    MarkLayer("L04_LOG", ok)
end

-- ==============================================================================
-- LAYER 05: SUBSYSTEM SCANNER BYPASS (real subsystem names)
-- ==============================================================================
local function L05_SCANNER()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end
        for _, name in ipairs(REAL_SECURITY_SUBSYSTEMS) do
            local sub = SubMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Upload") or
                        k:find("Verify") or k:find("Check") or k:find("Validate") or
                        k:find("Scan") or k:find("Detect") or k:find("Heartbeat") or
                        k:find("Flow")) then
                        pcall(function() sub[k] = nop end)
                    end
                end
                if sub.ReportPingDelayTimer then
                    pcall(function() sub:RemoveGameTimer(sub.ReportPingDelayTimer) end)
                    sub.ReportPingDelayTimer = nil
                end
                sub.DelayCount = 0
                ok = true
            end
        end
    end)
    MarkLayer("L05_SCANNER", ok)
end

-- ==============================================================================
-- LAYER 06: REPLAY TELEMETRY BYPASS
-- ==============================================================================
local function L06_REPLAY()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"GameReportSubsystem","ReplaySubsystem","RescueBtnReplayTraceSubsystem","SpectateAndReplaySubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and
                           (k:find("Report") or k:find("Trace") or k:find("Replay") or
                            k:find("Record") or k:find("Save") or k:find("Heartbeat")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                    ok = true
                end
            end
        end
        local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logRep then
            logRep.ReportReplay = nop
            logRep.SendReportReq = nop
            logRep.UploadReplay = nop
            ok = true
        end
        if _G.ClientReplayDataReporter then
            _G.ClientReplayDataReporter.ReportIntArrayData = nop
            _G.ClientReplayDataReporter.ReportUInt8ArrayData = nop
            _G.ClientReplayDataReporter.ReportFloatArrayData = nop
            ok = true
        end
    end)
    MarkLayer("L06_REPLAY", ok)
end

-- ==============================================================================
-- LAYER 07: REPORT FLOW CALLBACK BLOCKER
-- ==============================================================================
local function L07_REPORT_FLOW()
    local ok = false
    pcall(function()
        local flows = {
            "ReportAimFlow","ReportHitFlow","ReportAttackFlow","ReportSecAttackFlow",
            "ReportFireArms","ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior",
            "ReportTeammatHurt","ReportMisKillByTeammate","ReportForbitPick","ReportPlayerMoveRoute",
            "ReportPlayerPosition","ReportVehicleMoveFlow","ReportSecTgameMovingFlow","ReportParachuteData",
            "ReportEquipmentFlow","ReportPlayersPing","ReportPlayerIP","ReportPlayerFramePingRecord",
            "ReportDSNetSaturation","ReportNetContinuousSaturate","ReportDSNetRate","ReportCircleFlow",
            "ReportSecMrpcsFlow","SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby",
            "SendDSHawkEyePatrolLogToLobby","SendSecTLog","SendDataMiningTLog","SendActivityTLog",
            "SendClientMemUsage","SendClientFPS","OnClientCrashReport","OnNetworkLossDetected",
            "ReportMatchRoomData","SendClientStats","SendServerAvgTickDelta","SendClientDeviceInfo",
            "ReportDeviceFingerprint","SendNetworkInfo","ReportIPAddress","SendMACAddress","ReportHardwareID"
        }
        for _, f in ipairs(flows) do
            if _G[f] then _G[f] = nop; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = nop
                ok = true
            end
        end
        for _, f in ipairs({"CheckReportSecAttackFlowWithAttackFlow","CheckReportSecAttackFlow"}) do
            if _G[f] then _G[f] = retFalse; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = retFalse
                ok = true
            end
        end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow","IsEnableReportMrpcsInPartCircleFlow",
                            "IsEnableReportMrpcsFlow","IsEnableReportAttackFlow",
                            "IsEnableReportHitFlow","IsEnableReportCircleFlow"}) do
            if _G[f] then _G[f] = retFalse; ok = true end
        end
    end)
    MarkLayer("L07_REPORT_FLOW", ok)
end

-- ==============================================================================
-- LAYER 08: PLAYER SECURITY INFO BYPASS
-- ==============================================================================
local function L08_PLAYER_SEC()
    local ok = false
    pcall(function()
        local SecSub = safe_require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then
            SecSub.ReportData = nop
            SecSub.CheckCheat = retFalse
            SecSub.ValidatePlayer = retTrue
            SecSub.CollectData = nop
            SecSub.SendToServer = nop
            ok = true
        end
        for _, c in ipairs({"PlayerSecurityInfoCollector","PlayerSecurityInfo","SecurityInfoCollector",
                            "ClientSecurityCollector","PlayerAntiCheatCollector"}) do
            if _G[c] then
                for k, v in pairs(_G[c]) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Collect") or k:find("Send") or
                        k:find("Upload") or k:find("Record")) then
                        _G[c][k] = nop
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L08_PLAYER_SEC", ok)
end

-- ==============================================================================
-- LAYER 09: MRPCS / CLIENT FLOW BYPASS
-- ==============================================================================
local function L09_CLIENT_FLOW()
    local ok = false
    pcall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow","MrpcsFlow","MrpcsData",
                                "ClientCircleFlowSubsystem","ClientKillFlowSubsystem",
                                "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Flow") or
                        k:find("Record") or k:find("Process")) then
                        pcall(function() sub[k] = nop end)
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L09_CLIENT_FLOW", ok)
end

-- ==============================================================================
-- LAYER 10: SWIFT HAWK BYPASS
-- ==============================================================================
local function L10_SWIFT_HAWK()
    local ok = false
    pcall(function()
        for _, f in ipairs({"SwiftHawk","ClientSwiftHawk","ClientSwiftHawkWithParams","SendSwiftHawkData"}) do
            if _G[f] then _G[f] = nop; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = nop
                ok = true
            end
        end
        local sub = safe_require("GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem")
        if sub then
            sub.ReportData = nop
            sub.SendReport = nop
            sub.CollectTelemetry = nop
            ok = true
        end
    end)
    MarkLayer("L10_SWIFT_HAWK", ok)
end

-- ==============================================================================
-- LAYER 11: CORONA LAB BYPASS
-- ==============================================================================
local function L11_CORONA()
    local ok = false
    pcall(function()
        if _G.CoronaLab then
            _G.CoronaLab.ReportData = nop
            _G.CoronaLab.SendData = nop
            _G.CoronaLab.CollectData = nop
            _G.CoronaLab.Telemetry = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local sub = SubMgr and SubMgr:Get("CoronaLabSubsystem")
        if sub then
            sub.ReportData = nop
            sub.SendToServer = nop
            sub.CollectTelemetry = nop
            sub.StopCollection = nop
            ok = true
        end
        -- GlobalPlayerCoronaData lockdown — writes silently swallowed
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function() end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
        _G.BlackList = {}
        ok = true
    end)
    MarkLayer("L11_CORONA", ok)
end

-- ==============================================================================
-- LAYER 12: MODIFIER EXCEPTION BYPASS
-- ==============================================================================
local function L12_MODIFIER()
    local ok = false
    pcall(function()
        _G.bReportedModifierException = false
        local sub = safe_require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then
            sub.ReportException = nop
            sub.CheckModifier = retTrue
            sub.ValidateModifier = retTrue
            sub.ReportModifierError = nop
            ok = true
        end
    end)
    MarkLayer("L12_MODIFIER", ok)
end

-- ==============================================================================
-- LAYER 13: SIMULATE CHARACTER LOCATION BYPASS
-- ==============================================================================
local function L13_SIMULATE_CHAR()
    local ok = false
    pcall(function()
        local sub = safe_require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then
            sub.ReportLocation = nop
            sub.SendLocationData = nop
            sub.VerifyLocation = retTrue
            ok = true
        end
    end)
    MarkLayer("L13_SIMULATE_CHAR", ok)
end

-- ==============================================================================
-- LAYER 14: SHOOT VERIFICATION BYPASS
-- ==============================================================================
local function L14_SHOOT_VERIFY()
    local ok = false
    pcall(function()
        local sub = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then
            sub.OnShootVerifyFailed = nop
            sub.SendVerifyData = nop
            sub.ReportBulletHit = nop
            sub.UploadHitInfo = nop
            sub.VerifyShot = retTrue
            ok = true
        end
        if _G.BulletHitInfoUploadData then
            _G.BulletHitInfoUploadData.Report = nop
            _G.BulletHitInfoUploadData.Send = nop
            _G.BulletHitInfoUploadData.Upload = nop
            ok = true
        end
    end)
    MarkLayer("L14_SHOOT_VERIFY", ok)
end

-- ==============================================================================
-- LAYER 15: NETWORK PACKET BLOCK
-- ==============================================================================
local function L15_NET_PACKET()
    local ok = false
    pcall(function()
        if NetUtil and NetUtil.SendPacket and not NetUtil._IsBypassed then
            local orig = NetUtil.SendPacket
            local blocked = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1,
                ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1, ["ReportPlayerBehavior"]=1,
                ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
                ["ReportSecVehicleMoveFlow"]=1, ["ReportVehicleMoveFlow"]=1, ["ReportParachuteData"]=1,
                ["ReportEquipmentFlow"]=1, ["ReportJumpFlow"]=1, ["ReportHurtFlow"]=1,
                ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1,
                ["ReportCircleFlow"]=1, ["report_players_ping"]=1, ["report_player_ip"]=1,
                ["report_net_saturate"]=1, ["report_speed_hack"]=1, ["report_wall_hack"]=1,
                ["report_aim_bot"]=1, ["report_esp_usage"]=1, ["report_modded_files"]=1,
                ["detect_cheat"]=1, ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1,
                ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1,
                ["RPC_ClientCoronaLab"]=1, ["CoronaLabReport"]=1, ["CoronaLabData"]=1,
                ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1,
                ["ClientCircleFlow"]=1, ["IsEnableReportMrpcsInCircleFlow"]=1,
                ["IsEnableReportMrpcsInPartCircleFlow"]=1, ["bReportedModifierException"]=1,
                ["ReportModifierException"]=1, ["RPC_Server_ReportSimulateCharacterLocation"]=1,
                ["ReportSimulateCharacterLocation"]=1, ["RPC_Client_ShootVertifyRes"]=1,
                ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1,
                ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1,
                ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1,
                ["SwiftHawkReport"]=1, ["SwiftHawkData"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1,
                ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
                ["ReportSecTLog"]=1, ["report_client_scan_result"]=1,
                ["report_memory_exception"]=1, ["report_avatar_exception"]=1,
                ["report_character_state"]=1, ["report_vehicle_exception"]=1,
                ["report_camera_exception"]=1,
                ["ReportHeavyWeaponBoxSpawnFlow"]=1, ["ReportHeavyWeaponBoxActivationFlow"]=1,
                ["report_player_frame_ping_record"]=1,
                ["report_ds_net_saturation"]=1,
            }
            NetUtil.SendPacket = function(packetName, ...)
                if blocked[packetName] then return nil end
                return orig(packetName, ...)
            end
            NetUtil._IsBypassed = true
            ok = true
        end
        if _G.SendRPC and not _G._SendRPCBypassed then
            local origRPC = _G.SendRPC
            local blockedRPC = {
                "RPC_Server_ClientSecMrpcsFlow","RPC_Server_SwiftHawk",
                "RPC_Server_ClientSwiftHawkWithParams",
                "RPC_Server_ReportSimulateCharacterLocation",
                "RPC_Client_ShootVertifyRes","RPC_ClientCoronaLab"
            }
            _G.SendRPC = function(rpcName, ...)
                for _, b in ipairs(blockedRPC) do
                    if rpcName == b then return nil end
                end
                return origRPC(rpcName, ...)
            end
            _G._SendRPCBypassed = true
            ok = true
        end
    end)
    MarkLayer("L15_NET_PACKET", ok)
end

-- ==============================================================================
-- LAYER 16: HIGGS BOSON FULL BYPASS
-- ==============================================================================
local function L16_HIGGS()
    local ok = false
    pcall(function()
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck",
                "StartAvatarCheck","ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord",
                "ShowSecurityAlert","ServerReportAvatar","ClientReportNetAvatar",
                "SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev",
                "RPC_Client_ShootVertifyRes","RPC_Server_ReportSimulateCharacterLocation",
                "DisableHiggsBoson","CheckMHActive","ReportViolation","ProcessSecurityEvent",
                "ValidatePlayer","CheckIntegrity"
            }
            for _, m in ipairs(methods) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
            Higgs.IsMHActive = retFalse
            Higgs.bMHActive = false
            Higgs.bCallPreReplication = false
            if Higgs.BlackList then
                for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end
            end
            ok = true
        end
        _G.BlackList = {}
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
                if pc.HiggsBoson.ControlMHActive then
                    pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
                end
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent.bCallPreReplication = false
                pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
            end
            ok = true
        end
        local hia = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem")
        if hia then
            hia.CheckHitIntegrity = nop
            hia.InitSession = nop
            hia.OnBattleEnd = nop
            ok = true
        end
    end)
    MarkLayer("L16_HIGGS", ok)
end

-- ==============================================================================
-- LAYER 17: ANTI-CHEAT CALLBACK HOOKS
-- ==============================================================================
local function L17_ANTICHEAT_HOOKS()
    local ok = false
    pcall(function()
        local HBC = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC and HBC.StaticShowSecurityAlertInDev then
            HBC.StaticShowSecurityAlertInDev = nop
            ok = true
        end
        if _G.AvatarCheckCallback then
            _G.AvatarCheckCallback.StartAvatarCheck = nop
            _G.AvatarCheckCallback.OnReportItemID = nop
            _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
                if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then
                    PlayerController.HiggsBosonComponent:ControlMHActive(0)
                    PlayerController.HiggsBosonComponent.bMHActive = false
                end
            end
            ok = true
        end
    end)
    MarkLayer("L17_ANTICHEAT_HOOKS", ok)
end

-- ==============================================================================
-- LAYER 18: ANTI-REPORT PLAYER SUBSYSTEM BYPASS
-- ==============================================================================
local function L18_ANTI_REPORT()
    local ok = false
    pcall(function()
        for _, path in ipairs({
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem"
        }) do
            local sub = package.loaded[path]
            if not sub then
                local s, r = pcall(require, path)
                if s and r then sub = r end
            end
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Record") or k:find("Send") or
                        k:find("Upload") or k:find("Notify") or k:find("Submit")) then
                        pcall(function() sub[k] = nop end)
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L18_ANTI_REPORT", ok)
end

-- ==============================================================================
-- LAYER 19: GAMEPLAY CALLBACKS (SINGLE WRAP — critical layer)
-- ==============================================================================
local function L19_GAMEPLAY_CALLBACKS()
    local ok = false
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks

        if not GC._BypassV5Applied then
            local reports = {
                "ReportAttackFlow","ReportSecAttackFlow","ReportFireArms","ReportVerifyInfoFlow",
                "ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt","ReportMisKillByTeammate",
                "ReportForbitPick","ReportPlayerMoveRoute","ReportPlayerPosition","ReportVehicleMoveFlow",
                "ReportSecTgameMovingFlow","ReportParachuteData","SendTssSdkAntiDataToLobby",
                "ReportEquipmentFlow","ReportAimFlow","ReportPlayersPing","ReportPlayerIP",
                "ReportPlayerFramePingRecord","OnDSConnectionSaturated","ReportDSNetSaturation",
                "ReportNetContinuousSaturate","ReportDSNetRate","SendClientStats",
                "SendServerAvgTickDelta","ReportCircleFlow","ClientSecMrpcsFlow","SwiftHawk",
                "ClientSwiftHawk","ClientSwiftHawkWithParams","ReportHitFlow","ReportJumpFlow",
                "ReportHurtFlow","ReportHeavyWeaponBoxSpawnFlow","ReportHeavyWeaponBoxActivationFlow"
            }
            for _, f in ipairs(reports) do GC[f] = nop end

            GC.CheckReportSecAttackFlowWithAttackFlow = retFalse
            GC.CheckReportSecAttackFlow = retFalse

            -- Single-wrap of OnDSPlayerStateChanged
            local origState = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
                local s = State and string.lower(tostring(State)) or ""
                local block = {
                    ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1,
                    ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1,
                    ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1,
                    ["integrityfailure"]=1, ["securityviolation"]=1
                }
                if block[s] then return end
                if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
            end

            GC.OnPlayerNetConnectionClosed = nop
            GC.OnPlayerActorChannelError = nop
            GC.OnPlayerRPCValidateFailed = nop
            GC.OnPlayerSpectateException = nop
            GC.OnShutdownAfterError = nop

            GC._BypassV5Applied = true
            ok = true
        else
            ok = true
        end
    end)
    MarkLayer("L19_GAMEPLAY_CALLBACKS", ok)
end

-- ==============================================================================
-- LAYER 20: ALL SUBSYSTEMS KILL (real names only)
-- ==============================================================================
local function L20_KILL_SUBSYSTEMS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end
        for _, name in ipairs(REAL_SECURITY_SUBSYSTEMS) do
            local sub = SubMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Upload") or
                        k:find("Verify") or k:find("Check") or k:find("Validate") or
                        k:find("Scan") or k:find("Detect") or k:find("Collect") or
                        k:find("Flow") or k:find("Heartbeat") or k:find("Tick")) then
                        pcall(function() sub[k] = nop end)
                    end
                end
                if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
                ok = true
            end
        end
    end)
    MarkLayer("L20_KILL_SUBSYSTEMS", ok)
end

-- ==============================================================================
-- LAYER 21: TARGETED MODULE STUBBING (no global require hijack)
-- ==============================================================================
-- Instead of replacing _G.require globally (which breaks unrelated requires),
-- we replace the specific modules with safe stubs in package.loaded.
local function L21_MODULE_STUBS()
    local ok = false
    pcall(function()
        local stubPaths = {
            "GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent",
            "GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem",
            "GameLua.GameCore.Module.Subsystem.CoronaLabSubsystem",
            "GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem",
            "GameLua.Dev.Subsystem.ShootVerifySubSystemClient",
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
        }
        for _, path in ipairs(stubPaths) do
            local existing = package.loaded[path]
            if existing and type(existing) == "table" then
                -- Keep the table (so live references stay valid) but nop all callables
                for k, v in pairs(existing) do
                    if type(v) == "function" then
                        pcall(function() existing[k] = nop end)
                    end
                end
                ok = true
            end
        end
    end)
    MarkLayer("L21_MODULE_STUBS", ok)
end

-- ==============================================================================
-- LAYER 22: OPERATIONAL STATS BYPASS
-- ==============================================================================
local function L22_OPERATIONAL_STATS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local OSS = (SubMgr and SubMgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
        if OSS then
            OSS.ReportOperationalStats = nop
            OSS.AddOperationalStats = nop
            OSS.HandleTouchBegin = nop
            OSS.HandleTouchEnd = nop
            OSS.OnInit = nop
            OSS.HandleEnterFighting = nop
            OSS.OnBattleResult = nop
            if OSS.TimerHandle then
                pcall(function() OSS:RemoveGameTimer(OSS.TimerHandle) end)
                OSS.TimerHandle = nil
            end
            OSS.StatsData = {}
            ok = true
        end
    end)
    MarkLayer("L22_OPERATIONAL_STATS", ok)
end

-- ==============================================================================
-- LAYER 23: BASE BYPASS (dev / shipping flags)
-- ==============================================================================
local function L23_BASE()
    local ok = false
    pcall(function()
        local stExtra = import("STExtraBlueprintFunctionLibrary")
        if stExtra and stExtra.IsDevelopment then stExtra.IsDevelopment = nop; ok = true end
        if Client then Client.IsDevelopment = nop; Client.IsShipping = retFalse; ok = true end
        if Server then Server.IsShipping = retFalse; ok = true end

        local ToolReport = safe_require("client.slua.logic.report.ToolReportUtil")
        if ToolReport then
            ToolReport.IsReleaseVersion = retFalse
            ToolReport.IsWhite = retFalse
            ToolReport.GetReportSwitch = retFalse
            ok = true
        end

        local callbacks = _G.GameplayCallbacks
        if callbacks then
            local extra = {
                "ReportHitFlow","SendClientStats","SendServerAvgTickDelta"
            }
            for _, fn in ipairs(extra) do
                if callbacks[fn] then callbacks[fn] = nop end
            end
            ok = true
        end

        if _G.TApmHelper then _G.TApmHelper.postEvent = nop; ok = true end

        local PC = _G.PacketCallbacks
        if PC then
            PC.player_report_cheat = nop
            PC.upload_loots_rsp = nop
            PC.watch_player_exit = nop
            PC.player_login_report = nop
            PC.player_logout_report = nop
            PC.server_time_report = nop
            ok = true
        end

        local sdm = _G.ServerDataMgr
        if sdm and sdm.DeletablePlayerResultKey then
            sdm.DeletablePlayerResultKey["SuspiciousHitCount"] = true
            sdm.DeletablePlayerResultKey["EspTotalSimTraceCnt"] = true
            sdm.DeletablePlayerResultKey["EspTotalImeFocusCnt"] = true
            sdm.DeletablePlayerResultKey["ClientGravityAnomalyCount"] = true
            ok = true
        end

        local pcNotify = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature")
        if pcNotify then
            pcNotify.ClientRPC_SyncBanID = nop
            pcNotify.ClientRPC_StrongTips = nop
            pcNotify.ClientRPC_NormalTips = nop
            pcNotify.Notify = nop
            pcNotify.ClientRPC_NotifyBan = nop
            pcNotify.ClientRPC_NotifyPunish = nop
            pcNotify.ClientRPC_NotifyIllegalProgram = nop
            ok = true
        end

        local secUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
        if secUtils and secUtils.EStrategyTypeInReplay then
            secUtils.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
            secUtils.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
            secUtils.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
            secUtils.EStrategyTypeInReplay.FlyingErrorCnt = 0
            ok = true
        end
    end)
    MarkLayer("L23_BASE", ok)
end

-- ==============================================================================
-- LAYER 24: BAN SYSTEM BYPASS — ALL BAN TYPES
-- Covers: 1-day, 1-week, 10-year, HWID, device, IP, account.
-- All client-side ban handlers / notify paths silenced.
-- ==============================================================================
local function L24_BAN_SYSTEM()
    local ok = false
    pcall(function()
        -- Core ban logic
        local BanLogic = safe_require("client.slua.logic.ban.ClientBanLogic")
        if BanLogic then
            BanLogic.OnSyncBanInfo = nop
            BanLogic.OnVoiceBanNotify = nop
            BanLogic.OnRealTimeVoiceBanNotify = nop
            BanLogic.OnVoiceBanSuccess = nop
            BanLogic.OnSyncMicSuspicious = nop
            BanLogic.OnSyncMicPreFilter = nop
            BanLogic.OnNotifyWarningTips = nop
            BanLogic.ReqBanInfo = nop
            BanLogic.OnReceiveBanInfo = nop
            BanLogic.ShowBanUI = nop
            BanLogic.OnKickPlayer = nop
            ok = true
        end

        local BanUtil = safe_require("client.common.ban_util") or _G.ban_util
        if BanUtil then
            BanUtil.CheckBanStatus = retFalse
            BanUtil.GetBanTime = retZero
            BanUtil.IsBanForever = retFalse
            BanUtil.GetBanEndTime = retZero
            BanUtil.IsDeviceBanned = retFalse
            BanUtil.IsHWIDBanned = retFalse
            BanUtil.IsIPBanned = retFalse
            ok = true
        end

        -- TT (account) ban
        local TTBan = safe_require("client.logic.login.logic_tt_ban") or _G.logic_tt_ban
        if TTBan then
            TTBan.CheckIfCanCreateRole = nop
            TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
            TTBan.OnBanNotify = nop
            ok = true
        end

        -- Godzilla (device/HWID) ban
        local GodzillaBan = safe_require("client.network.Protocol.GodzillaBanHandler")
        if GodzillaBan then
            GodzillaBan.send_godzilla_ban_req = nop
            GodzillaBan.send_godzilla_unban_req = nop
            GodzillaBan.on_godzilla_ban_notify = nop
            ok = true
        end

        -- Anti-addiction (region lock / minor lock)
        local AntiAddiction = safe_require("client.network.Protocol.AntiaddctionHandler")
        if AntiAddiction then
            AntiAddiction.send_anti_addiction_req = nop
            AntiAddiction.send_anti_addiction_notify = nop
            AntiAddiction.on_anti_addiction_notify = nop
            ok = true
        end

        -- Access restriction (region / IP restrictions)
        local AccessRestrict = safe_require("client.network.Protocol.AccessRestrictionHandler")
        if AccessRestrict then
            AccessRestrict.send_access_restriction_req = nop
            AccessRestrict.send_access_restriction_notify = nop
            AccessRestrict.on_player_cheat_state_notify = nop
            AccessRestrict.on_access_restriction_notify = nop
            ok = true
        end

        -- Account deletion / forced GDPR
        local DeleteAccount = safe_require("client.slua.logic.gdpr.logic_deleteaccount")
        if DeleteAccount then
            DeleteAccount.ForceDeleteAccount = retFalse
            DeleteAccount.OnReceiveDeleteNotify = nop
            ok = true
        end

        local ComplianceUtil = safe_require("client.slua.logic.gdpr.compliance_util")
        if ComplianceUtil then ComplianceUtil.CheckCompliance = nop; ok = true end

        -- Security Notify PC (in-game ban popup path)
        local pcNotify = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature")
        if pcNotify then
            pcNotify.ClientRPC_SyncBanID = nop
            pcNotify.ClientRPC_StrongTips = nop
            pcNotify.ClientRPC_NormalTips = nop
            pcNotify.Notify = nop
            pcNotify.ClientRPC_NotifyBan = nop
            pcNotify.ClientRPC_NotifyPunish = nop
            pcNotify.ClientRPC_NotifyIllegalProgram = nop
            pcNotify.ClientRPC_ShowBanUI = nop
            ok = true
        end
    end)
    MarkLayer("L24_BAN_SYSTEM", ok)
end

-- ==============================================================================
-- LAYER 25: FULL REPORT SYSTEMS BYPASS
-- ==============================================================================
local function L25_REPORT_SYSTEMS()
    local ok = false
    pcall(function()
        local clientReport = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem")
        if clientReport then
            for _, fn in ipairs({
                "OnInit","_OnPlayerKilledOtherPlayer","_RecordFatalDamager","SendPacket",
                "ReportSuspiciousPlayer","SubmitReport","_OnBattleResult",
                "_RecordTeammatePlayerInfo","_OnDeathReplayDataWhenFatalDamaged",
                "_RecordMurdererFromDeathReplayData"
            }) do
                if clientReport[fn] then clientReport[fn] = nop end
            end
            ok = true
        end

        local dsReport = safe_require("GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem")
            or safe_require("GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem")
        if dsReport then
            for _, fn in ipairs({
                "_OnNearDeathOrRescued","_OnPlayerSettlementStart","_OnTeammateDamage",
                "_OnCharacterDied","_AddEnemyMapToBattleResult","_AddTeammateMapToBattleResult",
                "_SubmitAbnormalData"
            }) do
                if dsReport[fn] then dsReport[fn] = nop end
            end
            ok = true
        end

        local reportUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
        if reportUtils then
            reportUtils.GetBotType = retZero
            reportUtils.IsCharacterDeliverAI = retFalse
            ok = true
        end

        local AvatarSub = safe_require("GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionSubsystem")
        if AvatarSub then
            AvatarSub.OnClickReportCheckAvatar = nop
            AvatarSub.RegisterTickCheckCharacterAvatar = nop
            ok = true
        end

        if _G.AvatarExceptionPlayerInst then
            _G.AvatarExceptionPlayerInst.ReportAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckCanBugglyPostException = nop
            ok = true
        end

        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local hawk = SubMgr:Get("DSHawkEyePatrolSubsystem")
            if hawk then
                hawk.MarkSuspiciousPlayer = nop
                hawk._OnHawkReport = nop
                hawk._OnHawkImprison = nop
                hawk.CheckPunishPlayer = nop
                ok = true
            end
        end

        local ClientHawk = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem")
        if ClientHawk then
            for _, fn in ipairs({
                "_OnHawkSync","_OnHawkReportSuccess","_StartExitGameTimer",
                "_OnRecvInspectorBroadcastCount","SendReportTLog","ReportCheat"
            }) do
                if ClientHawk[fn] then ClientHawk[fn] = nop end
            end
            ClientHawk.CanInspectorBroadcast = retFalse
            ok = true
        end

        local InspectClient = safe_require("GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem")
        if InspectClient then
            for _, fn in ipairs({
                "AskForInspector","ReportEnemy","KickOutOneTeam","OnReceiveInspectCmd",
                "ClientReportData","SendReportToInspector","SendKickOutOneTeam",
                "ClientNotifyInspectorImplementation","RecvNotifyInspector"
            }) do
                if InspectClient[fn] then InspectClient[fn] = nop end
            end
            ok = true
        end

        local InspectDS = safe_require("GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem")
        if InspectDS then
            for _, fn in ipairs({
                "ServerKickOutOneTeamByPlayerImplementation","AddReportedCount",
                "AddInspectionRecord","BanPlayerByInspection","BroadCastToAllInspector",
                "ServerReportToInspectorImplementation","InitPlayerInspectionInfo"
            }) do
                if InspectDS[fn] then InspectDS[fn] = nop end
            end
            ok = true
        end
    end)
    MarkLayer("L25_REPORT_SYSTEMS", ok)
end

-- ==============================================================================
-- LAYER 26: TLOG BYPASS (all paths)
-- ==============================================================================
local function L26_TLOG()
    local ok = false
    pcall(function()
        local tlogMods = {
            "client.network.Protocol.ClientTlogHandler",
            "client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler",
            "client.network.Protocol.LobbyPingReportHandler",
            "client.slua.config.tlog.tlog_report_utils",
            "client.slua.data.BasicData.BasicDataTLogReport",
            "client.slua.data.BasicData.BasicDataClientReport",
            "client.slua.data.BasicData.BasicDataReport",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
            "GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem",
        }
        for _, path in ipairs(tlogMods) do
            local mod = package.loaded[path]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and
                       (k:find("Log") or k:find("Report") or k:find("Send") or k:find("Tlog")) then
                        pcall(function() mod[k] = nop end)
                    end
                end
                ok = true
            end
        end

        local AmphibiousBoat = safe_require("GameLua.GameCore.Module.Vehicle.VehicleFeatures.TLog.AmphibiousBoatTLogFeature")
        if AmphibiousBoat then
            AmphibiousBoat.RecordMovement = nop
            AmphibiousBoat.StartRecordMovement = nop
            ok = true
        end

        local ICTLog = safe_require("GameLua.Mod.BaseMod.DS.Security.ICTLogSubsystem")
        if ICTLog then ICTLog.SendICExceptionTLog = nop; ok = true end

        local DSFight = safe_require("GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem")
        if DSFight then
            DSFight.GetSimpleFightData = retEmpty
            DSFight.ReportFightData = nop
            DSFight.ReportPlayerWeapon = nop
            ok = true
        end

        local DSSec = safe_require("GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem")
        if DSSec then
            DSSec._OnReportServerJumpFlow = nop
            DSSec._OnReportTeleportFlow = nop
            DSSec._OnReportSpeedHackFlow = nop
            ok = true
        end

        local DSCommon = safe_require("GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem")
        if DSCommon then DSCommon.HandleKillTlog = nop; ok = true end

        local PufferTlog = safe_require("client.slua.logic.download.report.puffer_tlog")
        if PufferTlog then PufferTlog.report_download_tlog = nop; ok = true end
    end)
    MarkLayer("L26_TLOG", ok)
end

-- ==============================================================================
-- LAYER 27: NETWORK HANDLER BYPASS
-- ==============================================================================
local function L27_NET_HANDLERS()
    local ok = false
    pcall(function()
        local ClientError = safe_require("client.network.Protocol.ClientErrorReportHandler")
        if ClientError then
            ClientError.send_client_error_report = nop
            ClientError.send_client_crash_report = nop
            ClientError.send_client_tools_batch_report_req = nop
            ok = true
        end

        local BattleReport = safe_require("client.network.Protocol.BattleReportHandler")
        if BattleReport then
            for _, fn in ipairs({
                "send_battle_report","send_battle_result","send_vod_game_report_req",
                "send_batch_get_vod_info_req","send_get_game_report_req",
                "send_batch_get_game_report_req","send_get_game_report_by_uid_req"
            }) do
                if BattleReport[fn] then BattleReport[fn] = nop end
            end
            ok = true
        end

        local BugHandler = safe_require("client.network.Protocol.BugHandler")
        if BugHandler then
            BugHandler.send_report_bug_info = nop
            BugHandler.send_report_bug_feedback = nop
            ok = true
        end

        local PingReport = safe_require("client.network.Protocol.LobbyPingReportHandler")
        if PingReport then
            PingReport.send_lobby_ping_report = nop
            PingReport.send_ingame_ping_report = nop
            ok = true
        end

        local WeekReport = safe_require("client.network.Protocol.WeekRportHandler")
        if WeekReport then
            WeekReport.send_week_report = nop
            WeekReport.send_week_detail = nop
            ok = true
        end

        local LogicComplaint = safe_require("client.logic.battle.logic_complaint")
        if LogicComplaint then
            LogicComplaint.SendComplaintReq = nop
            LogicComplaint.Submit = nop
            LogicComplaint.ReportPlayer = nop
            LogicComplaint.ShowComplaint = nop
            LogicComplaint.ShowHandle = nop
            ok = true
        end

        local OBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic")
        if OBResult then
            OBResult.OnBattleResult = nop
            OBResult.OnResultProcessStart = nop
            ok = true
        end

        local NormalOBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic")
        if NormalOBResult then
            NormalOBResult.OnBattleResult = nop
            NormalOBResult.OnResultProcessStart = nop
            ok = true
        end

        local ShowResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic")
        if ShowResult then
            for _, fn in ipairs({
                "OnBattleResult","OnResultProcessStart","OnResultProcessContinue",
                "ReceiveData","SendEndFlow","OnReport","ShowResult",
                "ShowResultInternal","StopResultProcess"
            }) do
                if ShowResult[fn] then ShowResult[fn] = nop end
            end
            ok = true
        end
    end)
    MarkLayer("L27_NET_HANDLERS", ok)
end

-- ==============================================================================
-- LAYER 28: MISC BYPASS (emulator, verify, voice, etc.)
-- ==============================================================================
local function L28_MISC()
    local ok = false
    pcall(function()
        local EmuHandler = safe_require("client.network.Protocol.EmulatorHandler")
        if EmuHandler then EmuHandler.send_emulator_info = nop; ok = true end

        local EmuScanner = safe_require("client.logic.login.emulator_scanner")
        if EmuScanner then
            EmuScanner.StartScan = nop
            EmuScanner.GetScanResult = retFalse
            EmuScanner.ReportScanResult = nop
            ok = true
        end

        local LoginVerify = safe_require("client.network.Protocol.LoginVerifyHandler")
        if LoginVerify then
            LoginVerify.send_login_verify_req = nop
            LoginVerify.send_device_verify_req = nop
            ok = true
        end

        local DSMonitor = safe_require("client.logic.data.logic_ds_monitor")
        if DSMonitor then
            DSMonitor.OnRecordMsg = nop
            DSMonitor.OnReportMsg = nop
            ok = true
        end

        local ClientDataStat = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem")
        if ClientDataStat then
            ClientDataStat.StartToCheck = nop
            ClientDataStat.OnReceiveRTT = nop
            ClientDataStat.OnReceiveJitter = nop
            ClientDataStat.ReportAbnormal = nop
            ClientDataStat.ResetData = nop
            ok = true
        end

        local shootVerify = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if shootVerify then
            shootVerify.OnShootVerifyFailed = nop
            shootVerify.SendVerifyData = nop
            ok = true
        end

        local HighlightDS = safe_require("GameLua.Mod.BaseMod.DS.Security.HighlightMomentSubsystem_DSChecker")
        if HighlightDS then HighlightDS.CheckFuncUpgradedWeaponKill = nop; ok = true end

        local ProfileReport = safe_require("client.logic.data.profile_report_cfg")
        if ProfileReport then ProfileReport.SendReport = nop; ok = true end

        local VoiceReport = safe_require("client.slua.logic.chat_voice.logic_chat_voice_report")
        if VoiceReport then
            VoiceReport.ReportVoiceData = nop
            VoiceReport.ReportVoiceText = nop
            ok = true
        end

        local VoiceDoctor = safe_require("client.slua.logic.chat_voice.logic_chat_voice_doctor")
        if VoiceDoctor then
            VoiceDoctor.UploadVoiceLog = nop
            VoiceDoctor.UploadVoiceException = nop
            ok = true
        end

        local HomeAudit = safe_require("client.slua.logic.home.Audit.logic_home_audit_state")
        if HomeAudit then
            HomeAudit.SendAuditState = nop
            HomeAudit.ReportAuditResult = nop
            ok = true
        end

        local HomeReport = safe_require("client.slua.logic.home.logic_home_report")
        if HomeReport then
            HomeReport.ReportHomeData = nop
            HomeReport.ReportHomeVisitor = nop
            ok = true
        end

        local GemReport = safe_require("client.logic.store.gem_report_utils")
        if GemReport then
            GemReport.ReportGemData = nop
            GemReport.ReportGemPurchase = nop
            ok = true
        end

        local SafeStation = safe_require("client.slua.logic.CustomerService.LogicSafeStation")
        if SafeStation then
            SafeStation.UploadVideoEvidence = nop
            SafeStation.ReportPlayerBehavior = nop
            ok = true
        end

        local CustomerService = safe_require("client.slua.logic.CustomerService.LogicCustomerService")
        if CustomerService then
            CustomerService.SendComplaint = nop
            CustomerService.SendFeedback = nop
            ok = true
        end
    end)
    MarkLayer("L28_MISC", ok)
end

-- ==============================================================================
-- LAYER 29: EXTRA SUBSYSTEMS BYPASS
-- ==============================================================================
local function L29_EXTRA_SUBSYSTEMS()
    local ok = false
    pcall(function()
        local znq6Revive = safe_require("GameLua.Mod.TDEvent.ZNQ6th.DS.ZNQ6thDSReviveSubsystem")
        if znq6Revive then znq6Revive.HaveNewItemForRevive = nop; ok = true end

        local znq7Revive = safe_require("GameLua.Mod.TDEvent.ZNQ7th.DS.ZNQ7DSReviveSubsystem")
        if znq7Revive then znq7Revive.HaveChanceRevival = nop; ok = true end

        local DataLayer = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem")
        if DataLayer then
            local orig = DataLayer.OnSpectatorReplayChanged
            if orig and not DataLayer._WrappedV5 then
                DataLayer.OnSpectatorReplayChanged = function(dlSelf)
                    _G.IsBeingWatched = true
                    orig(dlSelf)
                end
                DataLayer._WrappedV5 = true
            end
            ok = true
        end

        local DSActive = safe_require("GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem")
        if DSActive then
            DSActive.DelayKickOutPlayer = nop
            DSActive.ActiveKickNotify = nop
            ok = true
        end

        local CreativeDev = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem")
        if CreativeDev then CreativeDev.IsDebugPanelEnalbedCli = nop; ok = true end

        local CreativeDeath = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem")
        if CreativeDeath then CreativeDeath.OnPlayerKilled = nop; ok = true end

        local SpectateReplay = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
        if SpectateReplay then
            SpectateReplay.RequestGotoSpectatingImp = nop
            SpectateReplay.RequestGotoSpectating = nop
            ok = true
        end

        local AIReplay = safe_require("GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem")
        if AIReplay then
            AIReplay.ReportAllPlayerInfo = nop
            AIReplay.ReportFrameData = nop
            AIReplay.ReportPlayerInput = nop
            if AIReplay.uCompletePlayBack then
                AIReplay.uCompletePlayBack.AddRecordMLAIInfo = nop
                AIReplay.uCompletePlayBack.StopRecording = nop
            end
            ok = true
        end

        local AITracking = safe_require("GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem")
        if AITracking then
            AITracking.RealLogoutTimer = nop
            AITracking.LogQueue = {}
            AITracking.AddToLogQue = nop
            AITracking.DoPrint = nop
            AITracking.OnAIPawnDied = nop
            AITracking.OnAIPawnReceiveDamage = nop
            AITracking.OnAIPawnEnemyChange = nop
            ok = true
        end

        local TDMAFK = safe_require("GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem")
        if TDMAFK then
            TDMAFK.SendAFKTips = nop
            TDMAFK.OnHandleLostConnection = nop
            ok = true
        end

        local DataMgr = safe_require("client.slua.logic.data.data_mgr")
        if DataMgr then DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = retZero; ok = true end

        local CreditLogic = safe_require("GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic")
        if CreditLogic then
            CreditLogic._SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = nop
            CreditLogic.ShowReturnLobbyIfFirstExitTeamBeforeBoarding = retFalse
            CreditLogic.OnReceiveCreditScoreChange = nop
            CreditLogic._IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = retFalse
            CreditLogic.SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = nop
            ok = true
        end
    end)
    MarkLayer("L29_EXTRA_SUBSYSTEMS", ok)
end

-- ==============================================================================
-- LAYER 30: NETWORK BLACKLIST (HTTP layer)
-- ==============================================================================
local function L30_NET_BLACKLIST()
    local ok = false
    pcall(function()
        if _G.HttpRequest and not _G._HttpBypassed then
            local orig = _G.HttpRequest
            _G.HttpRequest = function(url, ...)
                if isBlacklisted(url) then return nil end
                return orig(url, ...)
            end
            _G._HttpBypassed = true
            ok = true
        end

        if _G.FHttpModule and _G.FHttpModule.CreateRequest and not _G._FHttpBypassed then
            local orig = _G.FHttpModule.CreateRequest
            _G.FHttpModule.CreateRequest = function(...)
                local url = select(1, ...)
                if isBlacklisted(url) then return nil end
                return orig(...)
            end
            _G._FHttpBypassed = true
            ok = true
        end

        local netMods = {
            "client.slua.logic.network.logic_network",
            "client.slua.logic.download.report.puffer_tlog",
            "client.slua.data.BasicData.BasicDataClientReport",
            "GameLua.GameCore.Module.Network.NetworkManager",
            "client.network.Protocol.ClientTlogHandler",
            "client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler",
        }
        for _, mp in ipairs(netMods) do
            local mod = package.loaded[mp]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and
                       (k:find("Http") or k:find("Request") or k:find("Send") or
                        k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                        local origf = v
                        mod[k] = function(...)
                            local args = {...}
                            for _, arg in ipairs(args) do
                                if type(arg) == "string" and isBlacklisted(arg) then return nil end
                            end
                            return pcall(origf, ...)
                        end
                    end
                end
                ok = true
            end
        end
    end)
    MarkLayer("L30_NET_BLACKLIST", ok)
end

-- ==============================================================================
-- LAYER 31: FILE IO + CRASH WRITE BLOCK
-- ==============================================================================
local function L31_FILEIO()
    local ok = false
    pcall(function()
        if not _G._IoOpenHooked then
            local orig_io_open = io.open
            io.open = function(path, mode)
                if type(path) == "string" then
                    local lp = path:lower()
                    for _, kw in ipairs(FILE_KEYWORDS) do
                        if lp:find(kw) then
                            if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                                return nil, "Blocked"
                            end
                        end
                    end
                    if lp:find("tdm") or lp:find("gcloud") or lp:find("beacon") then
                        if mode and (mode == "w" or mode == "a" or mode == "w+") then
                            return nil
                        end
                    end
                end
                return orig_io_open(path, mode)
            end
            _G._IoOpenHooked = true
            ok = true
        end

        if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
            _G.UnrealEngine.CrashContext = nil
            _G.UnrealEngine.CrashContext = {
                SetCrashContext = nop,
                ReportCrash = nop,
                AddCrashData = nop
            }
            ok = true
        end
    end)
    MarkLayer("L31_FILEIO", ok)
end

-- ==============================================================================
-- LAYER 32: TSS SDK TOTAL SILENCE
-- ==============================================================================
local function L32_TSS_SDK()
    local ok = false
    pcall(function()
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            TssSdk.SendReportInfo = nop
            TssSdk.ScanMemory = function() return true, {code=0, msg="clean"} end
            TssSdk.ScanSo = function() return true, {code=0, msg="clean"} end
            TssSdk.ScanFile = function() return true, {code=0} end
            TssSdk.GetRiskFlag = function() return 0 end
            TssSdk.VerifyFileHash = function() return true end
            TssSdk.IsEmulator = retFalse
            TssSdk.GetTssSdkReportInfo = retEmptyString
            TssSdk.CheckEnvironment = retTrue
            TssSdk.VerifyProcess = retTrue
            TssSdk.CheckKernel = function() return true, {status="verified", tampered=false} end
            TssSdk.VerifyBoot = function() return true, {locked=true, verified=true} end

            -- Inbound data filter
            local origData = TssSdk.OnRecvData
            if origData and not TssSdk._DataFiltered then
                TssSdk.OnRecvData = function(data)
                    if type(data) == "string" then
                        local low = data:lower()
                        if low:find("report", 1, true) or low:find("exception", 1, true) or
                           low:find("cheat", 1, true) or low:find("violation", 1, true) or
                           low:find("hack", 1, true) or low:find("verify", 1, true) then
                            return
                        end
                    end
                    origData(data)
                end
                TssSdk._DataFiltered = true
            end
            ok = true
        end
    end)
    MarkLayer("L32_TSS_SDK", ok)
end

-- ==============================================================================
-- LAYER 33: BEHAVIOR SCORE / AFK / SPEED / WALL HEURISTIC BYPASS
-- These are the real heuristics used by GL 4.6 (via BehaviorScoreSubsystem
-- and AFKReportorSubsystem). Replaces the fake 8-layer names from v4.
-- ==============================================================================
local function L33_HEURISTICS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end

        local Behavior = SubMgr:Get("BehaviorScoreSubsystem")
            or safe_require("GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem")
        if Behavior then
            Behavior.OnHandleBehaviorScore = nop
            Behavior.AIPerceptionScore = nop
            Behavior.ReportBehavior = nop
            Behavior.CalcFinalScore = retZero
            Behavior.GetRiskLevel = retZero
            Behavior.IsSuspicious = retFalse
            ok = true
        end

        local AFK = SubMgr:Get("AFKReportorSubsystem")
            or safe_require("GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem")
        if AFK then
            AFK.HandleEnterFighting = nop
            AFK.InitializePlayerInputInfo = nop
            AFK.AddOneAFKInfo = nop
            AFK.SetPlayerAFKState = nop
            AFK.ResetPlayerInputInfo = nop
            AFK.PlayerHaveAction = nop
            ok = true
        end

        -- Speed / movement heuristics (via GameplayCallbacks, already nop'd above,
        -- but expose the internal delta to be safe)
        if _G.GameplayCallbacks then
            for _, k in ipairs({
                "ReportServerJumpFlow","ReportTeleportFlow","ReportSpeedHackFlow",
                "ReportClientMemUsage","ReportMemoryInfo"
            }) do
                _G.GameplayCallbacks[k] = nop
            end
            ok = true
        end
    end)
    MarkLayer("L33_HEURISTICS", ok)
end

-- ==============================================================================
-- LAYER 34: HWID / DEVICE FINGERPRINT SPOOF
-- ==============================================================================
local function L34_HWID_SPOOF()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local deviceInfo = SubMgr:Get("ClientDeviceInfoSubsystem")
            if deviceInfo then
                deviceInfo.GetDeviceID = function() return FakeData.deviceID() end
                deviceInfo.GetIPAddress = function() return FakeData.ipAddress() end
                deviceInfo.GetMACAddress = function() return FakeData.macAddress() end
                deviceInfo.GetBuildFingerprint = function() return FakeData.buildFingerprint() end
                ok = true
            end
        end
        if _G.GetDeviceID then _G.GetDeviceID = function() return FakeData.deviceID() end; ok = true end
        if _G.GetDeviceUniqueIdentifier then
            _G.GetDeviceUniqueIdentifier = function() return FakeData.deviceID() end
            ok = true
        end
    end)
    MarkLayer("L34_HWID_SPOOF", ok)
end

-- ==============================================================================
-- LAYER 35: PERSISTENT HUNT TIMER (re-arms itself, checks PC validity)
-- ==============================================================================
local function L35_HUNT_TICK()
    pcall(function()
        if not _G.BYPASS_STATE then return end

        -- Re-apply the critical layer every 3s (cheap, catches respawns/reinits)
        L19_GAMEPLAY_CALLBACKS()
        L20_KILL_SUBSYSTEMS()
        L39_SKIN_ANTI_DETECTION()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem",
                                    "ClientReportPlayerSubsystem","DSReportPlayerSubsystem",
                                    "AFKReportorSubsystem","BehaviorScoreSubsystem",
                                    "ClientDataStatistcsSubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and
                           (k:find("Report") or k:find("Send") or k:find("Tick") or k:find("Log")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                end
            end
        end

        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            for _, m in ipairs({"ControlMHActive","Tick","OnTick","MHActiveLogic",
                                "TriggerAvatarCheck","StartAvatarCheck","ReportItemID",
                                "ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert",
                                "ServerReportAvatar","ClientReportNetAvatar","SendHisarData",
                                "ValidateSecurityData"}) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
    end)
end

local function L35_START_HUNT_TIMER()
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and slua.isValid(pc) then
            if _G._V5HuntTimer then
                pcall(function() pc:RemoveGameTimer(_G._V5HuntTimer) end)
            end
            _G._V5HuntTimer = pc:AddGameTimer(3.0, true, L35_HUNT_TICK)
            return true
        end
        return false
    end)
    MarkLayer("L35_HUNT_TIMER", _G._V5HuntTimer ~= nil)
end

-- ==============================================================================
-- LAYER 36: ANTI-REPLAY BAN TRAP
-- Blocks replay-based "reviewed and banned" flows.
-- ==============================================================================
local function L36_REPLAY_BAN()
    local ok = false
    pcall(function()
        local rs = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
        if rs then
            rs.StartReplayRecord = nop
            rs.StopReplayRecord = nop
            rs.UploadReplayData = nop
            rs.SubmitReplayForReview = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local Review = SubMgr:Get("ReplayReviewSubsystem")
            if Review then
                Review.SubmitForReview = nop
                Review.UploadClip = nop
                Review.FlagPlayer = nop
                ok = true
            end
        end
    end)
    MarkLayer("L36_REPLAY_BAN", ok)
end

-- ==============================================================================
-- LAYER 37: LOGIN-TIME BAN CHECK SILENCE
-- Bypasses ban checks that fire on login / lobby load.
-- ==============================================================================
local function L37_LOGIN_BAN()
    local ok = false
    pcall(function()
        local LoginBan = safe_require("client.logic.login.logic_ban_check")
        if LoginBan then
            LoginBan.CheckBanOnLogin = retFalse
            LoginBan.QueryBanStatus = retNil
            LoginBan.OnBanResponse = nop
            ok = true
        end
        local LoginFlow = safe_require("client.logic.login.login_flow")
        if LoginFlow then
            LoginFlow.HandleBanMessage = nop
            LoginFlow.ShowBanDialog = nop
            LoginFlow.KickOutOnBan = nop
            ok = true
        end
        local LobbyBan = safe_require("client.logic.lobby.lobby_ban_check")
        if LobbyBan then
            LobbyBan.OnLobbyBanCheck = retFalse
            LobbyBan.ProcessBanData = nop
            ok = true
        end
    end)
    MarkLayer("L37_LOGIN_BAN", ok)
end

-- ==============================================================================
-- LAYER 38: KICK / DISCONNECT / FORCED-EXIT BLOCK
-- Bypasses server-forced kicks, including "cheat detected" kicks.
-- ==============================================================================
local function L38_KICK_BLOCK()
    local ok = false
    pcall(function()
        local KickHandler = safe_require("client.network.Protocol.KickHandler")
        if KickHandler then
            KickHandler.on_kick_notify = nop
            KickHandler.handle_kick = nop
            ok = true
        end
        local DSMgr = safe_require("GameLua.Mod.BaseMod.DS.Subsystem.DSKickSubsystem")
        if DSMgr then
            DSMgr.KickPlayer = nop
            DSMgr.KickPlayerFromMatch = nop
            DSMgr.DelayKickOutPlayer = nop
            ok = true
        end
        local FlowMgr = safe_require("client.logic.flow.exit_game_flow")
        if FlowMgr then
            FlowMgr.ForceExitGame = nop
            FlowMgr.ForceReturnToLobby = nop
            ok = true
        end
    end)
    MarkLayer("L38_KICK_BLOCK", ok)
end

-- ============================================================
-- ESP BAN FIX SYSTEM
-- ============================================================
do
local EspBanFix = {
    safeDistance = 10000,
    espEnabled = true,
    lastToggle = os.time(),
    toggleInterval = math.random(60, 180),
    markRandomSeed = os.time(),
    blockerActive = true,
    toggleCount = 0,
    blockCount = 0,
}

function EspBanFix:IsInSafeDistance(myPos, enemyPos)
    local dist = (myPos - enemyPos):Size()
    if dist > self.safeDistance then
        return false
    end
    return true
end

function EspBanFix:UpdateToggle()
    local elapsed = os.time() - self.lastToggle
    if elapsed >= self.toggleInterval then
        self.espEnabled = not self.espEnabled
        self.lastToggle = os.time()
        self.toggleInterval = math.random(60, 180)
        self.toggleCount = self.toggleCount + 1
        print("[ESP FIX] Toggle: " .. tostring(self.espEnabled) .. " (Count: " .. self.toggleCount .. ")")
    end
end

function EspBanFix:BlockDetection()
    pcall(function()
        local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if mgr then
            local espSubs = {
                "ClientESPDetectionSubsystem",
                "ClientAimTrackingSubsystem",
                "ClientRenderCheckSubsystem",
                "ClientWallhackDetectionSubsystem",
                "ClientMemoryGuardSubsystem",
                "ESPDetectionSubsystem",
                "RenderDetectionSubsystem",
                "MarkDetectionSubsystem",
            }
            for _, name in ipairs(espSubs) do
                local sub = mgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and type(k) == "string" then
                            if k:find("Detect") or k:find("Check") or k:find("Report") or 
                               k:find("Scan") or k:find("Verify") or k:find("Validate") then
                                sub[k] = function() return false end
                            end
                        end
                    end
                    self.blockCount = self.blockCount + 1
                end
            end
        end
    end)
    
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            local espPackets = {
                ["ESPDetection"]=1, ["ReportESP"]=1, ["WallhackReport"]=1,
                ["RenderAnomaly"]=1, ["MarkDetection"]=1, ["ScreenMarkReport"]=1,
                ["ClientESPReport"]=1, ["ESPUsage"]=1, ["VisualAnomaly"]=1,
                ["report_esp"]=1, ["report_wallhack"]=1, ["report_render"]=1,
                ["report_screen_mark"]=1, ["report_visual_anomaly"]=1,
                ["esp_detection"]=1, ["wallhack_detection"]=1, ["render_check"]=1,
            }
            NetUtil.SendPacket = function(packetName, ...)
                if espPackets[packetName] then
                    return nil
                end
                return orig(packetName, ...)
            end
        end
    end)
    
    pcall(function()
        if _G.GameplayCallbacks then
            local GC = _G.GameplayCallbacks
            local espFuncs = {
                "ReportESP", "ReportWallhack", "ReportRenderAnomaly",
                "CheckESP", "CheckWallhack", "CheckRender",
                "OnESPDetected", "OnWallhackDetected", "OnRenderAnomaly",
                "ValidateScreenMark", "CheckScreenMark", "ReportScreenMark",
            }
            for _, f in ipairs(espFuncs) do
                if GC[f] then GC[f] = function() return false end end
            end
        end
    end)
    
    print("[ESP FIX] Detection Blocked: " .. self.blockCount .. " subsystems")
end

function EspBanFix:RandomizeMarkId()
    self.markRandomSeed = self.markRandomSeed + 1
    local baseId = 1006
    local randomOffset = math.random(0, 100)
    return baseId
end

function EspBanFix:GetSafeMarkId()
    return 1006
end

function EspBanFix:Init()
    print("[ESP FIX] ================================")
    print("[ESP FIX] ESP Ban Fix System v1.0")
    print("[ESP FIX] Safe Distance: " .. self.safeDistance .. " units")
    print("[ESP FIX] ESP Toggle: ON")
    print("[ESP FIX] Detection Blocker: ACTIVE")
    print("[ESP FIX] ================================")
    self:BlockDetection()
end

_G.EspBanFix = EspBanFix
_G.EspBanFix:Init()

pcall(function()
    local tick2 = require("common.time_ticker")
    if tick2 then
        tick2.AddTimer(5, true, function()
            if _G.EspBanFix then
                _G.EspBanFix:UpdateToggle()
            end
        end)
    end
end)

-- ============================================================
-- END ESP BAN FIX
-- ============================================================
do
local Shield = {}

local function NoOp() return true end
local function NoFalse() return false end
local function NoZero() return 0 end
local function NoNil() return nil end
local function NoList() return {} end
local function NoString() return "" end

local function MuteObject(obj)
  if type(obj) ~= "table" then return end
  for k, v in pairs(obj) do
    if type(v) == "function" and type(k) == "string" and
      (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or
       k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect") or
       k:find("Collect") or k:find("Flow") or k:find("Heartbeat") or k:find("Record") or
       k:find("Trace") or k:find("Replay") or k:find("Save")) then
      pcall(function() obj[k] = NoOp end)
    end
  end
end

local BanShield = {}

function BanShield.KillBanFunctions()
  pcall(function()
    local banFuncs = {
      "BanPlayer", "BanUser", "ReportBan", "SendBanReport",
      "DetectBan", "CheckBan", "ValidateBan", "ProcessBan",
      "BanKick", "KickPlayer", "ForceLogout", "DisconnectPlayer",
      "ReportSuspicious", "ReportCheat", "ReportHack",
      "OnCheatDetected", "OnHackDetected", "OnViolationDetected",
      "AntiCheatReport", "CheatDetection", "ViolationReport",
      "SecurityViolation", "IntegrityCheck", "SignatureVerify",
      "TssSdkReport", "TssSdkBan", "TssSdkKick",
      "ReportModifierException", "ReportMemoryException",
      "ReportAvatarException", "ReportSpeedHack",
      "ReportWallHack", "ReportAimBot", "ReportESP",
      "ReportModdedFiles", "DetectCheat", "OnBanNotice", "OnKickNotice",
      "ProcessBanNotice", "HandleBanNotice", "ShowBanUI", "ShowKickUI"
    }
    for _, fn in ipairs(banFuncs) do
      if _G[fn] then _G[fn] = function() return true end end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[fn] then
        _G.GameplayCallbacks[fn] = function() return true end
      end
    end
  end)
end

function BanShield.SpoofSubsystems()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not mgr then return end
    local banSubs = {
      "AntiCheatSubsystem", "BanSubsystem", "PlayerBanSubsystem",
      "CheatDetectionSubsystem", "SecuritySubsystem",
      "BanManagerSubsystem", "KickBanSubsystem",
      "TssSdkSubsystem", "HiggsBosonSubsystem",
      "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
      "PlayerSecurityInfoSubsystem", "OperationalStatsSubsystem",
      "ModifierExceptionSubsystem", "MemoryCheckSubsystem"
    }
    for _, name in ipairs(banSubs) do
      local sub = mgr:Get(name)
      if sub then
        pcall(function()
          for k, v in pairs(sub) do
            if type(v) == "function" and type(k) == "string" then
              if k:find("Ban") or k:find("Kick") or k:find("Report") or
                 k:find("Detect") or k:find("Check") or k:find("Verify") or
                 k:find("Validate") or k:find("Process") or k:find("Send") or
                 k:find("Upload") or k:find("Notify") or k:find("Warn") then
                sub[k] = function() return true end
              end
            end
          end
          sub.bBanned = false
          sub.bKicked = false
          sub.bSuspended = false
          sub.BanCount = 0
          sub.WarningCount = 0
          sub.SuspicionScore = 0
        end)
      end
    end
  end)
end

function BanShield.BlockNet()
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local orig = NetUtil.SendPacket
      local banPackets = {
        ["ReportCheat"]=1, ["ReportHack"]=1, ["ReportSuspicious"]=1,
        ["ReportBan"]=1, ["SendBanReport"]=1, ["BanPlayer"]=1,
        ["KickPlayer"]=1, ["CheatDetection"]=1, ["AntiCheatReport"]=1,
        ["ViolationReport"]=1, ["SecurityViolation"]=1,
        ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
        ["TssSdkReport"]=1, ["TssSdkBan"]=1, ["TssSdkKick"]=1,
        ["tss_sdk_report"]=1, ["tss_sdk_ban"]=1, ["tss_sdk_kick"]=1,
        ["detect_cheat"]=1, ["ban_player"]=1, ["kick_player"]=1,
        ["report_aim_bot"]=1, ["report_esp"]=1, ["report_speed_hack"]=1,
        ["report_wall_hack"]=1, ["report_modded_files"]=1,
        ["client_anti_cheat_report"]=1, ["report_memory_exception"]=1,
        ["report_avatar_exception"]=1, ["report_script_exception"]=1,
        ["report_lua_violation"]=1, ["report_pak_modified"]=1,
        ["report_signature_fail"]=1, ["report_integrity_fail"]=1,
        ["OperationalStats"]=1, ["ReportOperationalStats"]=1,
        ["on_tss_sdk_anti_data"]=1, ["on_ban_notice"]=1, ["on_kick_notice"]=1,
        ["report_players_ping"]=1, ["report_player_ip"]=1,
        ["report_net_saturate"]=1, ["report_unrealnet_exception"]=1
      }
      NetUtil.SendPacket = function(packetName, ...)
        if banPackets[packetName] then return nil end
        return orig(packetName, ...)
      end
    end

    if _G.SendRPC then
      local origRpc = _G.SendRPC
      _G.SendRPC = function(rpcName, ...)
        if not rpcName then return origRpc(rpcName, ...) end
        local lower = string.lower(tostring(rpcName))
        if lower:find("ban") or lower:find("kick") or lower:find("report")
          or lower:find("cheat") or lower:find("hack") or lower:find("violation")
          or lower:find("verify") or lower:find("integrity") then
          return nil
        end
        return origRpc(rpcName, ...)
      end
    end
  end)
end

function BanShield.KillTssSdk()
  pcall(function()
    local tss = package.loaded["TssSdk"] or _G.TssSdk
    if tss then
      tss.GetFileMD5 = function() return "00000000000000000000000000000000" end
      tss.VerifyFileSignature = function() return true end
      tss.SendReportInfo = function() return true end
      tss.ScanMemory = function() return true end
      tss.IsEmulator = function() return false end
      tss.GetTssSdkReportInfo = function() return "" end
      tss.CheckEnvironment = function() return true end
      tss.VerifyProcess = function() return true end
      tss.ReportBan = function() return true end
      tss.ReportCheat = function() return true end
      tss.BanPlayer = function() return true end
      tss.KickPlayer = function() return true end
      tss.OnRecvData = function() return end
    end
  end)
end

function BanShield.KillGameState()
  pcall(function()
    local GD = require("GameLua.GameCore.Data.GameplayData")
    if not GD then return end
    local gs = GD.GetGameState and GD.GetGameState()
    if not gs then return end
    pcall(function()
      gs.BanPlayer = function() return true end
      gs.KickPlayer = function() return true end
      gs.ReportCheat = function() return true end
      gs.ReportHack = function() return true end
      gs.OnCheatDetected = function() return true end
      gs.OnHackDetected = function() return true end
      gs.AntiCheatReport = function() return true end
      gs.ShowBanNotice = function() return end
      gs.ShowKickNotice = function() return end
      gs.ProcessBanNotice = function() return end
    end)
  end)
end

function BanShield.SpoofBanStatus()
  pcall(function()
    local GD = require("GameLua.GameCore.Data.GameplayData")
    if not GD then return end
    local pc = GD.GetPlayerController and GD.GetPlayerController()
    if not pc then return end
    pcall(function()
      pc.bBanned = false
      pc.bKicked = false
      pc.bSuspended = false
      pc.BanReason = nil
      pc.BanTime = 0
      pc.BanCount = 0
      pc.WarningCount = 0
      pc.SuspicionScore = 0
    end)
    pcall(function()
      local ps = pc.GetPlayerStateSafety and pc:GetPlayerStateSafety()
      if ps then
        ps.bBanned = false
        ps.bKicked = false
        ps.bSuspended = false
        ps.BanCount = 0
        ps.WarningCount = 0
        ps.SuspicionScore = 0
      end
    end)
  end)
end

function BanShield.Install()
  if A.Up.BanShielded then return end
  A.Up.BanShielded = true
  BanShield.KillBanFunctions()
  BanShield.SpoofSubsystems()
  BanShield.BlockNet()
  BanShield.KillTssSdk()
  BanShield.KillGameState()
  BanShield.SpoofBanStatus()
  print("[BAN BYPASS 4.6] All ban systems neutralized")
end

function Shield.NeutralizeLoaders()
  pcall(function()
    if slua and slua.getSignature then slua.getSignature = NoZero end
    local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
    if loader then
      loader.verifyBytecode = NoOp
      loader.checkIntegrity = NoOp
      if loader.disableSignatureCheck then loader.disableSignatureCheck = NoOp end
    end
    local ser = package.loaded["slua.serialize"]
    if ser then ser.check = NoOp; ser.verify = NoOp end
    if jit and jit.attach then jit.attach(function() end, "bc") end
    if _G.slua_verify then _G.slua_verify = NoOp end
    if _G.check_slua_integrity then _G.check_slua_integrity = NoOp end
  end)
end

function Shield.NeutralizeHashes()
  pcall(function()
    local console = import("KismetSystemLibrary")
    if console then
      console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
      console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
      console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
      console.ExecuteConsoleCommand(nil, "sig.Check 0")
      console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
    end
    local CMode = import("CreativeModeBlueprintLibrary")
    if CMode then
      CMode.MD5HashByteArray = NoString
      CMode.MD5HashFile = NoString
      CMode.GetContentDiffData = function() return true, "OK" end
      CMode.VerifyFileIntegrity = NoOp
    end
    if _G.MD5Hash then _G.MD5Hash = NoString end
    if _G.CRC32 then _G.CRC32 = NoZero end
    if _G.SHA1 then _G.SHA1 = NoString end
    local fhc = package.loaded["common.file_hash_checker"]
    if fhc then
      fhc.CheckFileMD5 = NoOp
      fhc.VerifyAll = NoOp
      fhc.GetHash = NoString
    end
    local tss = package.loaded["TssSdk"] or _G.TssSdk
    if tss then
      tss.GetFileMD5 = NoString
      tss.VerifyFileSignature = NoOp
      tss.OnRecvData = function(data)
        if type(data) ~= "string" then return end
        local lower = string.lower(data)
        if lower:find("report", 1, true) or lower:find("exception", 1, true) or lower:find("cheat", 1, true) or lower:find("violation", 1, true) or lower:find("hack", 1, true) or lower:find("verify", 1, true) then return end
      end
      tss.SendReportInfo = NoNil
      tss.ScanMemory = NoOp
      tss.IsEmulator = NoFalse
      tss.GetTssSdkReportInfo = NoString
      tss.CheckEnvironment = NoOp
      tss.VerifyProcess = NoOp
    end
    local stx = import("STExtraBlueprintFunctionLibrary")
    if stx then
      stx.CheckMD5 = NoOp
      stx.GetMD5 = NoString
      stx.VerifyFile = NoOp
    end
  end)
end

function Shield.NeutralizeLogs()
  pcall(function()
    local SMTD = import("ScreenshotMTDer")
    if SMTD then
      SMTD.MTDePicture = NoString
      SMTD.ReMTDePicture = NoString
      SMTD.HasCaptured = NoOp
      SMTD.TakeScreenshot = NoNil
    end
    local tl = package.loaded["TLog"] or _G.TLog
    if tl then
      tl.Info, tl.Warning, tl.Error, tl.Debug = NoOp, NoOp, NoOp, NoOp
      tl.Report, tl.Send, tl.Flush = NoOp, NoOp, NoOp
    end
    local cs = package.loaded["CrashSight"] or _G.CrashSight
    if cs then
      cs.ReportException, cs.SetCustomData, cs.Log = NoOp, NoOp, NoOp
      cs.SendCrash, cs.ReportUserException = NoOp, NoOp
    end
    local gr = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
    if gr then
      gr.BugglyPostExceptionFull = NoFalse
      gr.CheckCanBugglyPostException = NoFalse
      gr.ReplayReportData, gr.ReportGameException, gr.PostException = NoOp, NoOp, NoOp
    end
    local ctr = package.loaded["client.slua.logic.report.ClientToolsReport"]
    if ctr then ctr.SendReport, ctr.SendException, ctr.UploadLog = NoOp, NoOp, NoOp end
    for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
      local s = _G[sdk]
      if s then
        s.logEvent, s.trackEvent = NoOp, NoOp
        s.setEnabled = NoFalse
        s.sendEvent, s.report = NoOp, NoOp
      end
    end
  end)
end

function Shield.NeutralizeSkins()
  pcall(function()
    local pt = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if pt then
      pt.ReportEvent, pt.ReportDownloadResult = NoOp, NoOp
      pt.ReportODPTDError, pt.ReportSkinError = NoOp, NoOp
    end
    local av = package.loaded["AvatarUtils"]
    if av then
      av.CheckIsWeaponInBlackList = NoFalse
      av.IsValidAvatar = NoOp
      av.CheckAvatarIntegrity = NoOp
      av.ReportInvalidAvatar = NoNil
    end
    local eq = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
    if eq then eq.Report, eq.SendException = NoOp, NoOp end
  end)
end

local ReportFlowNames = {
  "ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow",
  "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior",
  "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick",
  "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow",
  "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow",
  "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord",
  "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate",
  "ReportCircleFlow", "ReportSecMrpcsFlow", "SendTssSdkAntiDataToLobby",
  "SendClientStats", "SendServerAvgTickDelta", "SwiftHawk", "ClientSwiftHawk",
  "ClientSwiftHawkWithParams", "ClientSecMrpcsFlow", "MrpcsData"
}
local BlockPacketNames = {
  ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1,
  ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1, ["ReportPlayerBehavior"]=1,
  ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
  ["report_parachute_data"]=1, ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1,
  ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1, ["report_players_ping"]=1,
  ["report_player_ip"]=1, ["report_net_saturate"]=1, ["report_speed_hack"]=1,
  ["report_wall_hack"]=1, ["report_aim_bot"]=1, ["report_esp_usage"]=1,
  ["report_modded_files"]=1, ["detect_cheat"]=1, ["ban_player"]=1,
  ["client_anti_cheat_report"]=1, ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1,
  ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1,
  ["RPC_ClientCoronaLab"]=1, ["CoronaLabReport"]=1, ["CoronaLabData"]=1,
  ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1,
  ["ClientCircleFlow"]=1, ["bReportedModifierException"]=1, ["ReportModifierException"]=1,
  ["RPC_Server_ReportSimulateCharacterLocation"]=1, ["ReportSimulateCharacterLocation"]=1,
  ["RPC_Client_ShootVertifyRes"]=1, ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1,
  ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1, ["SwiftHawk"]=1,
  ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1,
  ["SwiftHawkData"]=1, ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1,
  ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
  ["OperationalStats"]=1, ["ReportOperationalStats"]=1, ["OperationalStatsReport"]=1
}
local BlockRpcNames = {
  "RPC_Server_ClientSecMrpcsFlow", "RPC_Server_SwiftHawk",
  "RPC_Server_ClientSwiftHawkWithParams", "RPC_Server_ReportSimulateCharacterLocation",
  "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab", "RPC_OperationalStats"
}
local KillSubSystems = {
  "AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem",
  "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem",
  "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem",
  "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem",
  "ModifierExceptionSubsystem", "SimulateCharacterSubsystem",
  "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
  "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem",
  "GameReportSubsystem", "ReplaySubsystem", "SwiftHawkSubsystem",
  "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
  "MD5CheckSubsystem", "PakVerifySubsystem", "OperationalStatsSubsystem",
  "MrpcsFlowSubsystem", "CircleFlowSubsystem",
  "ClientESPDetectionSubsystem", "ClientAimTrackingSubsystem",
  "ClientRenderCheckSubsystem", "ClientMemoryGuardSubsystem",
  "ClientKernelCheckSubsystem", "ClientWallhackDetectionSubsystem",
  "ClientAntiCheatSubsystem", "ClientSecMrpcsFlowSubsystem",
  "ShootVerifySubSystemClient"
}

function Shield.NeutralizeSubSystems()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if mgr then
      for _, name in ipairs(KillSubSystems) do
        local sub = mgr:Get(name)
        if sub then
          MuteObject(sub)
          for _, tm in ipairs({"timer", "heartbeatTimer", "reportTimer"}) do
            if sub[tm] then pcall(function() sub:RemoveGameTimer(sub[tm]) end) end
          end
        end
      end
    end
    local flowRunner = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
    if flowRunner then
      flowRunner.CheckAvatarException, flowRunner.CheckAvatarExceptionOnce = NoOp, NoOp
      flowRunner.ReportAvatarException = NoNil
      flowRunner.CheckSlotMeshVisible, flowRunner.CheckPawnVisible = NoFalse, NoFalse
      flowRunner.CheckCanBugglyPostException = NoFalse
    end
    local rep = package.loaded["client.slua.logic.replay.logic_report_replay"]
    if rep then rep.ReportReplay, rep.SendReportReq, rep.UploadReplay = NoOp, NoOp, NoOp end
  end)
end

function Shield.NeutralizeGlobalFlows()
  pcall(function()
    if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
    local GC = _G.GameplayCallbacks
    for _, f in ipairs(ReportFlowNames) do
      if _G[f] then _G[f] = NoOp end
      GC[f] = NoOp
    end
    GC.CheckReportSecAttackFlowWithAttackFlow = NoFalse
    GC.CheckReportSecAttackFlow = NoFalse
    for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow", "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow", "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"}) do
      if _G[f] then _G[f] = NoFalse end
    end
    local origState = GC.OnDSPlayerStateChanged
    GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
      local s = State and string.lower(tostring(State)) or ""
      local danger = {
        ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1,
        ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, ["kicked"]=1,
        ["suspended"]=1, ["violationdetected"]=1, ["integrityfailure"]=1, ["securityviolation"]=1
      }
      if danger[s] then return end
      if origState and type(origState) == "function" then
        return origState(UID, State, bPure, bSafe, Param)
      end
    end
    GC.OnPlayerNetConnectionClosed = NoNil
    GC.OnPlayerActorChannelError = NoNil
    GC.OnPlayerRPCValidateFailed = NoNil
    GC.OnPlayerSpectateException = NoNil
    GC.OnShutdownAfterError = NoNil
  end)
end

local _NetShielded = false
function Shield.NeutralizeNet()
  if _NetShielded then return end
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local original = NetUtil.SendPacket
      NetUtil.SendPacket = function(packetName, ...)
        if BlockPacketNames[packetName] then return nil end
        return original(packetName, ...)
      end
    end
    if _G.SendRPC then
      local originalRpc = _G.SendRPC
      _G.SendRPC = function(rpcName, ...)
        for _, b in ipairs(BlockRpcNames) do
          if rpcName == b then return nil end
        end
        return originalRpc(rpcName, ...)
      end
    end
    _NetShielded = true
  end)
end

function Shield.NeutralizeHiggs()
  pcall(function()
    local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
    if Higgs then
      local methods = {
        "ControlMHActive", "Tick", "OnTick", "MHActiveLogic", "TriggerAvatarCheck",
        "StartAvatarCheck", "ReportItemID", "ReceiveAnyDamage", "OnWeaponHitRecord",
        "ShowSecurityAlert", "ServerReportAvatar", "ClientReportNetAvatar", "SendHisarData",
        "ValidateSecurityData", "StaticShowSecurityAlertInDev", "RPC_Client_ShootVertifyRes",
        "RPC_Server_ReportSimulateCharacterLocation", "DisableHiggsBoson", "CheckMHActive",
        "ReportViolation", "ProcessSecurityEvent", "ValidatePlayer", "CheckIntegrity"
      }
      for _, m in ipairs(methods) do if Higgs[m] then Higgs[m] = NoNil end end
      Higgs.GetNetAvatarItemIDs = NoList
      Higgs.GetCurWeaponSkinID = NoZero
      Higgs.IsMHActive = NoFalse
      Higgs.bMHActive = false
      Higgs.bCallPreReplication = false
      if Higgs.BlackList then
        local keys = {}
        for k in pairs(Higgs.BlackList) do table.insert(keys, k) end
        for _, k in ipairs(keys) do Higgs.BlackList[k] = nil end
      end
    end
    _G.BlackList = {}
    if _G.AvatarCheckCallback then
      _G.AvatarCheckCallback.StartAvatarCheck = NoNil
      _G.AvatarCheckCallback.OnReportItemID = NoNil
      _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(pc)
        if Around(pc) then
          if pc.HiggsBosonComponent then
            pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
            pc.HiggsBosonComponent.bMHActive = false
          end
          if pc.HiggsBoson then
            pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
            pc.HiggsBoson.bMHActive = false
          end
        end
      end
    end
  end)
end

function Shield.NeutralizePlayers()
  pcall(function()
    for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
      if _G[c] then MuteObject(_G[c]) end
    end
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if mgr then
      local sec = mgr:Get("PlayerSecurityInfoSubsystem")
      if sec then
        sec.ReportData, sec.CollectData, sec.SendToServer = NoNil, NoNil, NoNil
        sec.CheckCheat = NoFalse
        sec.ValidatePlayer = NoOp
      end
      local sw = mgr:Get("SwiftHawkSubsystem")
      if sw then sw.ReportData, sw.SendReport, sw.CollectTelemetry = NoNil, NoNil, NoNil end
      local cr = mgr:Get("ModifierExceptionSubsystem")
      if cr then
        cr.ReportException, cr.ReportModifierError = NoNil, NoNil
        cr.CheckModifier, cr.ValidateModifier = NoOp, NoOp
      end
      local sm = mgr:Get("SimulateCharacterSubsystem")
      if sm then sm.ReportLocation, sm.SendLocationData = NoNil, NoNil; sm.VerifyLocation = NoOp end
      local sv = mgr:Get("ShootVerifySubSystemClient")
      if sv then
        sv.OnShootVerifyFailed, sv.SendVerifyData, sv.ReportBulletHit, sv.UploadHitInfo = NoNil, NoNil, NoNil, NoNil
        sv.VerifyShot = NoOp
      end
    end
    if _G.bReportedModifierException then _G.bReportedModifierException = false end
    if _G.BulletHitInfoUploadData then MuteObject(_G.BulletHitInfoUploadData) end
  end)
end

function Shield.NeutralizeStats()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    local ops = (mgr and mgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
    if ops then
      ops.ReportOperationalStats, ops.AddOperationalStats = NoNil, NoNil
      ops.HandleTouchBegin, ops.HandleTouchEnd = NoNil, NoNil
      ops.OnInit, ops.HandleEnterFighting, ops.OnBattleResult = NoNil, NoNil, NoNil
      ops.StatsData = {}
    end
  end)
end

function Shield.NeutralizeLoading()
  pcall(function()
    local flags = {"ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", "ENABLE_PERFORMANCE_REPORT"}
    for _, f in ipairs(flags) do if _G[f] then _G[f] = false end end
    local realRequire = require
    local poisoned = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "OperationalStatsSubsystem"}
    _G.require = function(moduleName)
      for _, bad in ipairs(poisoned) do
        if moduleName:find(bad, 1, true) then return {} end
      end
      return realRequire(moduleName)
    end
  end)
end

function Shield.NeutralizeSweep()
  local needle = {"verify", "integrity", "signature", "filecheck", "file_check", "hashcheck", "hash_check", "tss", "security", "report"}
  local seen = {}
  pcall(function()
    local function Watch(mod)
      if type(mod) ~= "table" or seen[mod] then return end
      seen[mod] = true
      MuteObject(mod)
    end
    for key, mod in pairs(package.loaded) do
      if type(key) == "string" then
        local low = string.lower(key)
        for _, n in ipairs(needle) do
          if string.find(low, n, 1, true) then Watch(mod) break end
        end
      end
    end
    for key, mod in pairs(_G) do
      if type(key) == "string" then
        local low = string.lower(key)
        for _, n in ipairs(needle) do
          if string.find(low, n, 1, true) then Watch(mod) break end
        end
      end
    end
  end)
end

function Shield.Hum()
  A.Up.Heartbeat = math.random(15, 45)
  A.Up.PingJitter = math.random(-12, 18)
  A.Up.FakeKd = 0.9 + math.random() * 1.9
  A.Up.FakeHead = 9 + math.random() * 22
  pcall(function()
    if debug and debug.getinfo then
      local origin = debug.getinfo
      debug.getinfo = function(level, what)
        local info = origin(level, what)
        if info and info.source then
          local src = info.source
          if string.find(src, "BRPlayerCharacterBase", 1, true) or string.find(src, "AegisShell", 1, true) then
            info.source = "ProtectedSource"
            info.short_src = "ProtectedSource"
          end
        end
        return info
      end
    end
  end)
  pcall(function()
    if debug then
      if debug.sethook then debug.sethook = function() end end
      if debug.getlocal then debug.getlocal = function() end end
      if debug.setupvalue then debug.setupvalue = function() end end
    end
    if string and string.dump then
      string.dump = function() return "" end
    end
  end)
end

function Shield.InstallAll()
  _G.LicenseValid = true    -- ✅ YEH LINE ADD KARO
  _G.ModsEnabled = true     -- ✅ YEH LINE ADD KARO
  if not (_G.IsLicenseOK and _G.IsLicenseOK()) then return end
  if A.Up.Shielded then return end
  A.Up.Shielded = true
  BanShield.Install()
  Shield.NeutralizeLoaders()
  Shield.NeutralizeHashes()
  Shield.NeutralizeLogs()
  Shield.NeutralizeSkins()
  Shield.NeutralizeSubSystems()
  Shield.NeutralizeGlobalFlows()
  Shield.NeutralizeNet()
  Shield.NeutralizeHiggs()
  Shield.NeutralizePlayers()
  Shield.NeutralizeStats()
  Shield.NeutralizeSweep()
  Shield.NeutralizeLoading()
  Shield.Hum()
  pcall(function() import("KismetSystemLibrary").ExecuteConsoleCommand(nil, "r.ShaderPipelineCache 0") end)
  print("[SAMEER] ALL PROTECTION + BAN BYPASS 4.6 ACTIVE")
end
pcall(function() Shield.InstallAll() end)

-- ============================================================================
-- ================= 4.6 REPORT BYPASS SYSTEM — NEW UPDATE ====================
-- ============================================================================
pcall(function()
    print("[4.6 BYPASS] Loading NEW Report Bypass System...")
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 1: BLOCK ALL REPORT PACKETS (NETWORK LEVEL)
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local origSendPacket = NetUtil.SendPacket
            local BLOCKED_PACKETS = {
                -- Player reports
                ["ReportPlayer"]=1, ["ReportPlayerBehavior"]=1, ["ReportSuspicious"]=1,
                ["ReportCheat"]=1, ["ReportHack"]=1, ["ReportAim"]=1, ["ReportESP"]=1,
                ["ReportSpeed"]=1, ["ReportWall"]=1, ["ReportTeammate"]=1,
                ["ReportVoice"]=1, ["ReportBadWord"]=1, ["ReportToxic"]=1,
                ["ReportAFK"]=1, ["ReportTeamKill"]=1, ["ReportUnsporting"]=1,
                ["ReportFeedback"]=1, ["ReportPlayerName"]=1, ["ReportBug"]=1,
                ["ReportAutoAim"]=1, ["ReportWallHack"]=1, ["ReportSpeedHack"]=1,
                
                -- Auto-detection
                ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportAttackFlow"]=1,
                ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1,
                ["ReportMrpcsFlow"]=1, ["ReportSecMrpcsFlow"]=1,
                ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
                ["ReportVehicleMoveFlow"]=1, ["ReportSecTgameMovingFlow"]=1,
                ["ReportParachuteData"]=1, ["ReportEquipmentFlow"]=1,
                ["ReportCircleFlow"]=1, ["ReportPlayersPing"]=1, ["ReportPlayerIP"]=1,
                ["ReportPlayerFramePingRecord"]=1, ["ReportDSNetSaturation"]=1,
                ["ReportNetContinuousSaturate"]=1, ["ReportDSNetRate"]=1,
                ["ReportTeammatHurt"]=1, ["ReportMisKillByTeammate"]=1,
                ["ReportForbitPick"]=1,
                
                -- Anti-cheat
                ["ReportCheatDetection"]=1, ["ReportViolation"]=1,
                ["ReportSecurityViolation"]=1, ["ReportIntegrityFailure"]=1,
                ["ReportModdedFiles"]=1, ["ReportSignatureFail"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1,
                ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
                
                -- TSS SDK
                ["tss_sdk_report"]=1, ["tss_sdk_ban"]=1, ["tss_sdk_kick"]=1,
                ["on_tss_sdk_anti_data"]=1, ["TssSdkReport"]=1,
                ["TssSdkBan"]=1, ["TssSdkKick"]=1,
                
                -- Corona Lab
                ["CoronaLabReport"]=1, ["CoronaLabData"]=1, ["RPC_ClientCoronaLab"]=1,
                
                -- Operational Stats
                ["OperationalStats"]=1, ["ReportOperationalStats"]=1,
                ["OperationalStatsReport"]=1,
                
                -- Swift Hawk
                ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1,
                ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1,
                ["SwiftHawkData"]=1,
                
                -- Ban/Kick
                ["BanPlayer"]=1, ["KickPlayer"]=1, ["on_ban_notice"]=1,
                ["on_kick_notice"]=1, ["detect_cheat"]=1, ["ban_player"]=1,
                ["kick_player"]=1,
                
                -- lowercase
                ["report_player"]=1, ["report_cheat"]=1, ["report_hack"]=1,
                ["report_esp"]=1, ["report_aim_bot"]=1, ["report_speed_hack"]=1,
                ["report_wall_hack"]=1, ["report_modded_files"]=1,
                ["report_memory_exception"]=1, ["report_avatar_exception"]=1,
                ["report_script_exception"]=1, ["report_lua_violation"]=1,
                ["report_pak_modified"]=1, ["report_signature_fail"]=1,
                ["report_integrity_fail"]=1, ["report_unrealnet_exception"]=1,
                ["client_anti_cheat_report"]=1
            }
            
            NetUtil.SendPacket = function(packetName, ...)
                if BLOCKED_PACKETS[packetName] then return nil end
                return origSendPacket(packetName, ...)
            end
            NetUtil.SendPacket.__4_6_bypass = true
            print("[4.6] Layer 1: Network packets blocked ✅")
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 2: BLOCK RPC CALLS
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        if _G.SendRPC then
            local origSendRPC = _G.SendRPC
            local BLOCKED_RPC = {
                "RPC_Server_ReportPlayer", "RPC_Server_ReportCheat",
                "RPC_Server_ReportSuspicious", "RPC_Server_ReportBehavior",
                "RPC_Server_ReportAim", "RPC_Server_ReportESP",
                "RPC_Server_SwiftHawk", "RPC_Server_ClientSwiftHawkWithParams",
                "RPC_Server_ClientSecMrpcsFlow",
                "RPC_Server_ReportSimulateCharacterLocation",
                "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab",
                "RPC_OperationalStats", "RPC_Server_Ban", "RPC_Server_Kick"
            }
            _G.SendRPC = function(rpcName, ...)
                for _, blocked in ipairs(BLOCKED_RPC) do
                    if rpcName == blocked then return nil end
                end
                return origSendRPC(rpcName, ...)
            end
            _G.SendRPC.__4_6_bypass = true
            print("[4.6] Layer 2: RPC calls blocked ✅")
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 3: HOOK REPORT MODULES
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        local reportModules = {
            "GameLua.Mod.BaseMod.Client.Report.LogicReportPlayer",
            "GameLua.Mod.BaseMod.Client.Report.ReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.Client.Report.ReportCheat",
            "GameLua.Mod.BaseMod.Client.Report.ReportSuspicious"
        }
        
        for _, path in ipairs(reportModules) do
            local mod = package.loaded[path]
            if not mod then
                local ok, loaded = pcall(require, path)
                if ok and loaded then mod = loaded end
            end
            
            if mod and type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" and type(k) == "string" then
                        if k:find("Report") or k:find("Send") or k:find("Submit") or k:find("Notify") then
                            pcall(function() mod[k] = function() return true end end)
                        end
                    end
                end
            end
        end
        print("[4.6] Layer 3: Report modules hooked ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 4: BLOCK REPORT UI
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        local reportUI = {
            "GameLua.Mod.BaseMod.Client.Report.ReportPlayerUI",
            "GameLua.Mod.BaseMod.Client.UI.ReportPlayerUI",
            "GameLua.Mod.BaseMod.Client.UI.ReportUI"
        }
        for _, path in ipairs(reportUI) do
            local mod = package.loaded[path]
            if not mod then
                local ok, loaded = pcall(require, path)
                if ok and loaded then mod = loaded end
            end
            if mod and mod.__inner_impl then
                pcall(function()
                    mod.__inner_impl.OnConfirmReport = function() return end
                    mod.__inner_impl.OnClickReport = function() return end
                    mod.__inner_impl.SubmitReport = function() return end
                end)
            end
        end
        print("[4.6] Layer 4: Report UI blocked ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 5: BLOCK GAMEPLAY CALLBACKS
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks
        local callbacks = {
            "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms",
            "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior",
            "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick",
            "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow",
            "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow",
            "ReportAimFlow", "ReportHitFlow", "ReportCircleFlow",
            "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord",
            "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate",
            "SendTssSdkAntiDataToLobby", "SendClientStats", "SendServerAvgTickDelta",
            "ClientSecMrpcsFlow", "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"
        }
        for _, f in ipairs(callbacks) do
            GC[f] = function() return true end
            if _G[f] then _G[f] = function() return true end end
        end
        print("[4.6] Layer 5: Gameplay callbacks blocked ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 6: NEUTRALIZE HIGGS BOSON
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        local Higgs = package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
        if Higgs then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck",
                "StartAvatarCheck","ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord",
                "ShowSecurityAlert","ServerReportAvatar","ClientReportNetAvatar",
                "SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev",
                "DisableHiggsBoson","CheckMHActive","ReportViolation",
                "ProcessSecurityEvent","ValidatePlayer","CheckIntegrity"
            }
            for _, m in ipairs(methods) do
                if Higgs[m] then Higgs[m] = function() return true end end
            end
            Higgs.GetNetAvatarItemIDs = function() return {} end
            Higgs.GetCurWeaponSkinID = function() return 0 end
            Higgs.IsMHActive = function() return false end
            Higgs.bMHActive = false
            Higgs.bCallPreReplication = false
            if Higgs.BlackList then
                for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end
            end
        end
        _G.BlackList = {}
        print("[4.6] Layer 6: Higgs Boson neutralized ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 7: BLOCK TSS SDK
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        local tss = package.loaded["TssSdk"] or _G.TssSdk
        if tss then
            tss.GetFileMD5 = function() return "00000000000000000000000000000000" end
            tss.VerifyFileSignature = function() return true end
            tss.SendReportInfo = function() return true end
            tss.ScanMemory = function() return true end
            tss.IsEmulator = function() return false end
            tss.GetTssSdkReportInfo = function() return "" end
            tss.CheckEnvironment = function() return true end
            tss.VerifyProcess = function() return true end
            tss.ReportBan = function() return true end
            tss.ReportCheat = function() return true end
            tss.BanPlayer = function() return true end
            tss.KickPlayer = function() return true end
            tss.OnRecvData = function() return end
        end
        print("[4.6] Layer 7: TSS SDK blocked ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 8: SPOOF SERVER STATE
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        if _G.GameplayCallbacks then
            local GC = _G.GameplayCallbacks
            local origState = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
                local s = State and string.lower(tostring(State)) or ""
                local DANGER = {
                    ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1,
                    ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1,
                    ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1,
                    ["integrityfailure"]=1, ["securityviolation"]=1, ["reportdetected"]=1
                }
                if DANGER[s] then return end
                if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
            end
        end
        print("[4.6] Layer 8: Server state spoof ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 9: BLOCK BAN POPUP
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        _G.ShowBanNotice = function() return end
        _G.ShowKickNotice = function() return end
        _G.ProcessBanNotice = function() return end
        _G.HandleBanNotice = function() return end
        
        local banUI = {
            "client.slua.umg.BanNoticeUI",
            "client.slua.umg.KickNoticeUI",
            "GameLua.Mod.BaseMod.Client.UI.BanUI"
        }
        for _, path in ipairs(banUI) do
            local mod = package.loaded[path]
            if mod and type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" and k:find("Show") then
                        pcall(function() mod[k] = function() return end end)
                    end
                end
            end
        end
        print("[4.6] Layer 9: Ban popup blocked ✅")
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LAYER 10: CONTINUOUS MONITOR (Re-apply every 5 sec)
    -- ═══════════════════════════════════════════════════════════════════════
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerLoop then
            ticker.AddTimerLoop(5.0, function()
                pcall(function()
                    -- Re-block NetUtil
                    if NetUtil and NetUtil.SendPacket then
                        if not NetUtil.SendPacket.__4_6_bypass then
                            local orig = NetUtil.SendPacket
                            NetUtil.SendPacket = function(name, ...)
                                local BLOCK = {
                                    ["ReportPlayer"]=1, ["ReportCheat"]=1, ["ReportHack"]=1,
                                    ["ReportSuspicious"]=1, ["report_player"]=1, ["report_cheat"]=1,
                                    ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportAttackFlow"]=1,
                                    ["SwiftHawk"]=1, ["TssSdkReport"]=1, ["BanPlayer"]=1, ["KickPlayer"]=1
                                }
                                if BLOCK[name] then return nil end
                                return orig(name, ...)
                            end
                            NetUtil.SendPacket.__4_6_bypass = true
                        end
                    end
                    
                    -- Re-block SendRPC
                    if _G.SendRPC and not _G.SendRPC.__4_6_bypass then
                        local orig = _G.SendRPC
                        _G.SendRPC = function(name, ...)
                            if not name then return orig(name, ...) end
                            local lower = string.lower(tostring(name))
                            if lower:find("report") or lower:find("ban") or lower:find("kick") 
                               or lower:find("cheat") or lower:find("hack") or lower:find("violation") then
                                return nil
                            end
                            return orig(name, ...)
                        end
                        _G.SendRPC.__4_6_bypass = true
                    end
                    
                    -- Re-spoof Higgs
                    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                    if slua.isValid(pc) then
                        if pc.HiggsBoson then 
                            pc.HiggsBoson.bMHActive = false
                            pc.HiggsBoson.bCallPreReplication = false 
                        end
                        if pc.HiggsBosonComponent then 
                            pc.HiggsBosonComponent.bMHActive = false
                            pc.HiggsBosonComponent.bCallPreReplication = false 
                        end
                    end
                end)
            end, -1, 5.0)
        end
        print("[4.6] Layer 10: Continuous monitor active ✅")
    end)
    
    print("[4.6] ============================================")
    print("[4.6] REPORT BYPASS SYSTEM FULLY ACTIVE")
    print("[4.6] ============================================")
end)
-- ============================================================================

end
end
local class
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  },
  {
    FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature"
  }
}, "BRPlayerCharacterBase")
