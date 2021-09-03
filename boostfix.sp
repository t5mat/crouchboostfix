#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name = "boostfix",
    version = "1.0.0",
    author = "https://github.com/t5mat",
    description = "Fixes buggy push triggers; prevents crouchboosting",
    url = "https://github.com/t5mat/boostfix",
};

#define SOLID_NONE (0)
#define FSOLID_NOT_SOLID (0x0004)

#define SF_TRIG_PUSH_ONCE (0x80)
#define SF_TRIG_PUSH_AFFECT_PLAYER_ON_LADDER (0x100)

#define VEC_HULL_MIN (view_as<float>({-16.0, -16.0, 0.0}))
#define VEC_HULL_MAX (view_as<float>({16.0, 16.0, 72.0}))
#define VEC_DUCK_HULL_MIN (view_as<float>({-16.0, -16.0, 0.0}))
#define VEC_DUCK_HULL_MAX (view_as<float>({16.0, 16.0, 54.0}))

#define CROUCHBOOST_TIME (0.25)

enum struct Engine
{
    int m_nSolidType;
    int m_usSolidFlags;
    int m_spawnflags;
    int m_vecBaseVelocity;
    int m_flLaggedMovementValue;
    int m_hGroundEntity;
    Handle PassesTriggerFilters_;
    int m_hMoveParent;
    int m_vecAbsOrigin;
    int m_angAbsRotation;
    int m_vecAbsVelocity;
    int m_flSpeed;
    int m_vecPushDir;

    void Initialize()
    {
        (this.m_nSolidType = FindSendPropInfo("CBaseEntity", "m_nSolidType")) == -1 && SetFailState("CBaseEntity::m_nSolidType");
        (this.m_usSolidFlags = FindSendPropInfo("CBaseEntity", "m_usSolidFlags")) == -1 && SetFailState("CBaseEntity::m_usSolidFlags");
        (this.m_spawnflags = FindSendPropInfo("CBaseTrigger", "m_spawnflags")) == -1 && SetFailState("CBaseTrigger::m_spawnflags");
        (this.m_vecBaseVelocity = FindSendPropInfo("CBasePlayer", "m_vecBaseVelocity")) == -1 && SetFailState("CBasePlayer::m_vecBaseVelocity");
        (this.m_flLaggedMovementValue = FindSendPropInfo("CBasePlayer", "m_flLaggedMovementValue")) == -1 && SetFailState("CBasePlayer::m_flLaggedMovementValue");
        (this.m_hGroundEntity = FindSendPropInfo("CBasePlayer", "m_hGroundEntity")) == -1 && SetFailState("CBasePlayer::m_hGroundEntity");

        GameData gd;
        (gd = new GameData("rngfix.games")) == null && SetFailState("rngfix.games");

        StartPrepSDKCall(SDKCall_Entity);
        PrepSDKCall_SetFromConf(gd, SDKConf_Virtual, "CBaseTrigger::PassesTriggerFilters");
        PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
        PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
        (this.PassesTriggerFilters_ = EndPrepSDKCall()) == null && SetFailState("CBaseTrigger::PassesTriggerFilters");

        delete gd;

        this.m_hMoveParent = -1;
        this.m_vecPushDir = -1;
    }

    void InitializeCBaseEntityOffsets(int entity)
    {
        if (this.m_hMoveParent != -1) {
            return;
        }

        (this.m_hMoveParent = FindDataMapInfo(entity, "m_hMoveParent")) == -1 && SetFailState("CBaseEntity::m_hMoveParent");
        (this.m_vecAbsOrigin = FindDataMapInfo(entity, "m_vecAbsOrigin")) == -1 && SetFailState("CBaseEntity::m_vecAbsOrigin");
        (this.m_angAbsRotation = FindDataMapInfo(entity, "m_angAbsRotation")) == -1 && SetFailState("CBaseEntity::m_angAbsRotation");
        (this.m_vecAbsVelocity = FindDataMapInfo(entity, "m_vecAbsVelocity")) == -1 && SetFailState("CBaseEntity::m_vecAbsVelocity");
        (this.m_flSpeed = FindDataMapInfo(entity, "m_flSpeed")) == -1 && SetFailState("CBaseEntity::m_flSpeed");
    }

    void InitializeCTriggerPushOffsets(int entity)
    {
        if (this.m_vecPushDir != -1) {
            return;
        }

        (this.m_vecPushDir = FindDataMapInfo(entity, "m_vecPushDir")) == -1 && SetFailState("CTriggerPush::m_vecPushDir");
    }

    bool PassesTriggerFilters(int entity, int other)
    {
        return SDKCall(this.PassesTriggerFilters_, entity, other);
    }
}

enum struct Client
{
    float origin[3];
    float velocity[3];
    int flags;
    float frame;
    bool touching[4096];
    float endTouchFrame[4096];
    bool endTouchDuck[4096];
}

bool g_late;
ConVar g_boostfix_pushfix;
ConVar g_boostfix_crouchboostfix;
Engine g_engine;
Client g_clients[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_CSGO) {
        FormatEx(error, err_max, "Not supported");
        return APLRes_Failure;
    }

    g_late = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_engine.Initialize();

    g_boostfix_pushfix = CreateConVar("boostfix_pushfix", "1", "Enable trigger_push fix", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_boostfix_crouchboostfix = CreateConVar("boostfix_crouchboostfix", "1", "Enable crouchboost prevention", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    if (g_late) {
        for (int e = 0; e < sizeof(Client::touching); ++e) {
            if ((e < 1 || e > sizeof(g_clients) - 1) && IsValidEntity(e)) {
                char classname[64];
                GetEntityClassname(e, classname, sizeof(classname));
                OnEntityCreated(e, classname);
            }
        }

        for (int c = 1; c <= MaxClients; ++c) {
            if (IsClientInGame(c)) {
                OnClientPutInServer(c);
            }
        }
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    g_engine.InitializeCBaseEntityOffsets(entity);

    if (StrEqual(classname, "trigger_push")) {
        g_engine.InitializeCTriggerPushOffsets(entity);

        for (int i = 0; i < sizeof(g_clients); ++i) {
            g_clients[i].touching[entity] = false;
        }

        SDKHook(entity, SDKHook_StartTouch, Hook_PushStartTouch);
        SDKHook(entity, SDKHook_EndTouch, Hook_PushEndTouch);
        SDKHook(entity, SDKHook_Touch, Hook_PushTouch);
    }
}

public void OnClientPutInServer(int client)
{
    g_clients[client].frame = 0.0;
    for (int i = 0; i < sizeof(Client::endTouchFrame); ++i) {
        g_clients[client].endTouchFrame[i] = -1.0;
    }

    SDKHook(client, SDKHook_PreThinkPost, Hook_ClientPreThinkPost);
}

void Hook_ClientPreThinkPost(int client)
{
    GetEntDataVector(client, g_engine.m_vecAbsOrigin, g_clients[client].origin);
    GetEntDataVector(client, g_engine.m_vecAbsVelocity, g_clients[client].velocity);
    g_clients[client].flags = GetEntityFlags(client);

    g_clients[client].frame += GetEntDataFloat(client, g_engine.m_flLaggedMovementValue);
}

Action Hook_PushStartTouch(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    if (g_boostfix_crouchboostfix.BoolValue && g_clients[other].endTouchFrame[entity] != -1.0 && g_clients[other].frame - g_clients[other].endTouchFrame[entity] < CROUCHBOOST_TIME / GetTickInterval()) {
        bool startTouchUnduck = false;

        if (!g_clients[other].endTouchDuck[entity]) {
            // Were we mid-air last tick?
            if (!(g_clients[other].flags & FL_ONGROUND)) {
                // Did we unduck?
                if ((g_clients[other].flags & FL_DUCKING) && !(GetEntityFlags(other) & FL_DUCKING)) {
                    // Had we not unducked, would we still be not touching the trigger?
                    float origin[3];
                    origin = g_clients[other].velocity;
                    ScaleVector(origin, GetTickInterval() * GetEntDataFloat(other, g_engine.m_flLaggedMovementValue));
                    AddVectors(origin, g_clients[other].origin, origin);
                    if (!DoesHullEntityIntersect(origin, VEC_DUCK_HULL_MIN, VEC_DUCK_HULL_MAX, entity)) {
                        // This StartTouch was caused by a mid-air unduck
                        startTouchUnduck = true;
                    }

                }
            }
        }

        // If this StartTouch happened too soon after the last EndTouch, and either:
        // - the last EndTouch was caused by a mid-air duck, or
        // - this StartTouch was caused by a mid-air unduck
        // then this StartTouch is considered "invalid", disable pushing so we don't get boosted again
        g_clients[other].touching[entity] = !(g_clients[other].endTouchDuck[entity] || startTouchUnduck);
    } else {
        g_clients[other].touching[entity] = true;
    }

    if (!g_clients[other].touching[entity]) {
        // Prevent outputs from being queued
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

Action Hook_PushEndTouch(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    g_clients[other].touching[entity] = false;
    g_clients[other].endTouchFrame[entity] = g_clients[other].frame;
    g_clients[other].endTouchDuck[entity] = false;

    // Were we mid-air last tick?
    if (!(g_clients[other].flags & FL_ONGROUND)) {
        // Did we duck?
        if (!(g_clients[other].flags & FL_DUCKING) && (GetEntityFlags(other) & FL_DUCKING)) {
            // Had we not ducked, would we still be touching the trigger?
            float origin[3];
            origin = g_clients[other].velocity;
            ScaleVector(origin, GetTickInterval() * GetEntDataFloat(other, g_engine.m_flLaggedMovementValue));
            AddVectors(origin, g_clients[other].origin, origin);
            if (DoesHullEntityIntersect(origin, VEC_HULL_MIN, VEC_HULL_MAX, entity)) {
                // This EndTouch was caused by a mid-air duck
                g_clients[other].endTouchDuck[entity] = true;
            }
        }
    }

    return Plugin_Continue;
}

Action Hook_PushTouch(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    if (!g_clients[other].touching[entity]) {
        return Plugin_Handled;
    }

    MoveType moveType = GetEntityMoveType(other);

    if (moveType == MOVETYPE_VPHYSICS) {
        return Plugin_Continue;
    }

    if (!g_boostfix_pushfix.BoolValue) {
        return Plugin_Continue;
    }

    // https://github.com/perilouswithadollarsign/cstrike15_src/blob/29e4c1fda9698d5cebcdaf1a0de4b829fa149bf8/game/server/triggers.cpp#L2545

    if (moveType == MOVETYPE_NONE || moveType == MOVETYPE_PUSH) {
        return Plugin_Handled;
    }

    if ((GetEntData(other, g_engine.m_nSolidType, 1) == SOLID_NONE) || (GetEntData(other, g_engine.m_usSolidFlags, 2) & FSOLID_NOT_SOLID)) {
        return Plugin_Handled;
    }

    if (GetEntDataEnt2(other, g_engine.m_hMoveParent) != -1) {
        return Plugin_Handled;
    }

    if (!g_engine.PassesTriggerFilters(entity, other)) {
        return Plugin_Handled;
    }

    float direction[3];
    {
        float rotation[3];
        GetEntDataVector(entity, g_engine.m_angAbsRotation, rotation);

        float local[3];
        GetEntDataVector(entity, g_engine.m_vecPushDir, local);

        float sy = Sine(DegToRad(rotation[1]));
        float cy = Cosine(DegToRad(rotation[1]));
        float sp = Sine(DegToRad(rotation[0]));
        float cp = Cosine(DegToRad(rotation[0]));
        float sr = Sine(DegToRad(rotation[2]));
        float cr = Cosine(DegToRad(rotation[2]));

        direction[0] = local[0] * (cp * cy) + local[1] * (sp * sr * cy - cr * sy) + local[2] * (sp * cr * cy + sr * sy);
        direction[1] = local[0] * (cp * sy) + local[1] * (sp * sr * sy + cr * cy) + local[2] * (sp * cr * sy - sr * cy);
        direction[2] = local[0] * (-sp) + local[1] * (sr * cp) + local[2] * (cr * cp);
    }

    float speed = GetEntDataFloat(entity, g_engine.m_flSpeed);

    float push[3];
    push = direction;
    ScaleVector(push, speed);

    if (GetEntData(entity, g_engine.m_spawnflags) & SF_TRIG_PUSH_ONCE) {
        float velocity[3];
        GetEntDataVector(other, g_engine.m_vecAbsVelocity, velocity);
        AddVectors(velocity, push, velocity);

        TeleportEntity(other, NULL_VECTOR, NULL_VECTOR, velocity);
        if (direction[2] > 0.0) {
            SetEntDataEnt2(other, g_engine.m_hGroundEntity, -1);
        }

        RemoveEdict(entity);
        return Plugin_Handled;
    }

    int flags = GetEntityFlags(other);

    if (flags & FL_BASEVELOCITY) {
        float base[3];
        GetEntDataVector(other, g_engine.m_vecBaseVelocity, base);
        AddVectors(push, base, push);
    }

    // https://forums.alliedmods.net/showpost.php?p=2561673&postcount=17

    float velocity[3];
    GetEntDataVector(other, g_engine.m_vecAbsVelocity, velocity);
    velocity[2] += push[2] * GetTickInterval() * GetEntDataFloat(other, g_engine.m_flLaggedMovementValue);
    push[2] = 0.0;

    TeleportEntity(other, NULL_VECTOR, NULL_VECTOR, velocity);
    SetEntDataVector(other, g_engine.m_vecBaseVelocity, push);
    SetEntityFlags(other, flags | FL_BASEVELOCITY);

    return Plugin_Handled;
}

bool g_DoesHullEntityIntersect_hit;

bool DoesHullEntityIntersect(const float origin[3], const float mins[3], const float maxs[3], int entity, int mask = PARTITION_TRIGGER_EDICTS)
{
    g_DoesHullEntityIntersect_hit = false;
    TR_EnumerateEntitiesHull(origin, origin, mins, maxs, mask, Trace_DoesHullEntityIntersect, entity);
    return g_DoesHullEntityIntersect_hit;
}

bool Trace_DoesHullEntityIntersect(int entity, any data)
{
    if (entity == data) {
        TR_ClipCurrentRayToEntity(MASK_ALL, entity);
        g_DoesHullEntityIntersect_hit = TR_DidHit();
        return false;
    }
    return true;
}
