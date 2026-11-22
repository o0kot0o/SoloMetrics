-- SoloMetrics: SecretSafety
-- The only helpers allowed to inspect possibly-secret values. They use only
-- issecretvalue() and type(), both of which are safe on secret values.

local _, ns = ...
local S = {}
ns.SecretSafety = S

function S.IsSecret(v)
    if issecretvalue then
        return issecretvalue(v) and true or false
    end
    return false
end

-- v if readable, otherwise nil. Use before ANY Lua logic on a value.
function S.Readable(v)
    if S.IsSecret(v) then return nil end
    return v
end

-- true if v is a number (secret or not). type() is safe on secrets.
function S.IsNumber(v)
    return type(v) == "number"
end
