#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name = "crouchboostfix",
    version = "2.0.0",
    author = "https://github.com/t5mat",
    description = "Prevents crouchboosting",
    url = "https://github.com/t5mat/crouchboostfix",
};

#define CROUCHBOOST_TIME (0.25)

#define MAX_ENTITIES (4096)

enum struct Engine
{
    int m_vecMins;
    int m_vecMaxs;
    int m_flLaggedMovementValue;

    int m_vecAbsOrigin;
    int m_vecAbsVelocity;

    void Initialize(int entity = -1, const char[] classname = "")
    {
        static bool start = false;
        if (!start) {
            start = true;
            (this.m_vecMins = FindSendPropInfo("CBaseEntity", "m_vecMins")) == -1 && SetFailState("CBaseEntity::m_vecMins");
            (this.m_vecMaxs = FindSendPropInfo("CBaseEntity", "m_vecMaxs")) == -1 && SetFailState("CBaseEntity::m_vecMaxs");
            (this.m_flLaggedMovementValue = FindSendPropInfo("CBasePlayer", "m_flLaggedMovementValue")) == -1 && SetFailState("CBasePlayer::m_flLaggedMovementValue");
        }

        static bool base = false;
        if (!base && entity != -1) {
            base = true;
            (this.m_vecAbsOrigin = FindDataMapInfo(entity, "m_vecAbsOrigin")) == -1 && SetFailState("CBaseEntity::m_vecAbsOrigin");
            (this.m_vecAbsVelocity = FindDataMapInfo(entity, "m_vecAbsVelocity")) == -1 && SetFailState("CBaseEntity::m_vecAbsVelocity");
        }
    }
}

enum struct Client
{
    float origin[3];
    float velocity[3];
    float mins[3];
    float maxs[3];
    int flags;
    float frame;
    bool touching[MAX_ENTITIES];
    float endTouchFrame[MAX_ENTITIES];
    bool endTouchDuck[MAX_ENTITIES];
}

bool g_late;
ConVar g_crouchboostfix_enabled;
Engine g_engine;
Client g_clients[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("crouchboostfix");
    g_late = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_engine.Initialize();

    g_crouchboostfix_enabled = CreateConVar("crouchboostfix_enabled", "1", "Enable crouchboost prevention", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig();

    HookEntityOutput("trigger_multiple", "OnStartTouch", Hook_EntityOutput);
    HookEntityOutput("trigger_multiple", "OnEndTouch", Hook_EntityOutput);
    HookEntityOutput("trigger_push", "OnStartTouch", Hook_EntityOutput);
    HookEntityOutput("trigger_push", "OnEndTouch", Hook_EntityOutput);
    HookEntityOutput("trigger_gravity", "OnStartTouch", Hook_EntityOutput);
    HookEntityOutput("trigger_gravity", "OnEndTouch", Hook_EntityOutput);

    if (g_late) {
        for (int e = 0; e < sizeof(Client::touching); ++e) {
            if (IsValidEntity(e)) {
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
    g_engine.Initialize(entity, classname);

    bool push = StrEqual(classname, "trigger_push");
    if (StrEqual(classname, "trigger_multiple") || push || StrEqual(classname, "trigger_gravity")) {
        for (int i = 0; i < sizeof(g_clients); ++i) {
            g_clients[i].touching[entity] = false;
        }

        SDKHook(entity, SDKHook_StartTouch, Hook_TriggerStartTouch);
        SDKHook(entity, SDKHook_EndTouchPost, Hook_TriggerEndTouchPost);
        if (push) {
            SDKHook(entity, SDKHook_Touch, Hook_TriggerPushTouch);
        }
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

Action Hook_EntityOutput(const char[] output, int caller, int activator, float delay)
{
    if (activator < 1 || activator > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    if (g_crouchboostfix_enabled.BoolValue && !g_clients[activator].touching[caller]) {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void Hook_ClientPreThinkPost(int client)
{
    GetEntDataVector(client, g_engine.m_vecAbsOrigin, g_clients[client].origin);
    GetEntDataVector(client, g_engine.m_vecAbsVelocity, g_clients[client].velocity);
    GetEntDataVector(client, g_engine.m_vecMins, g_clients[client].mins);
    GetEntDataVector(client, g_engine.m_vecMaxs, g_clients[client].maxs);
    g_clients[client].flags = GetEntityFlags(client);

    g_clients[client].frame += GetEntDataFloat(client, g_engine.m_flLaggedMovementValue);
}

Action Hook_TriggerStartTouch(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    if (g_clients[other].endTouchFrame[entity] != -1.0 && g_clients[other].frame - g_clients[other].endTouchFrame[entity] < CROUCHBOOST_TIME / GetTickInterval()) {
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
                    if (!DoesHullEntityIntersect(origin, g_clients[other].mins, g_clients[other].maxs, entity)) {
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

    return Plugin_Continue;
}

void Hook_TriggerEndTouchPost(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return;
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
            if (DoesHullEntityIntersect(origin, g_clients[other].mins, g_clients[other].maxs, entity)) {
                // This EndTouch was caused by a mid-air duck
                g_clients[other].endTouchDuck[entity] = true;
            }
        }
    }
}

Action Hook_TriggerPushTouch(int entity, int other)
{
    if (other > sizeof(g_clients) - 1) {
        return Plugin_Continue;
    }

    if (g_crouchboostfix_enabled.BoolValue && !g_clients[other].touching[entity]) {
        return Plugin_Handled;
    }

    return Plugin_Continue;
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
