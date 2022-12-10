local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local path = require "mason-core.path"
local Optional = require "mason-core.optional"
local expr = require "mason-core.installer.registry.expr"

local M = {}

local delegates = {
    ["python"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write python wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            local python = platform.is.win and "python" or "python3"
            return ctx:write_shell_exec_wrapper(
                bin,
                ("%s %q"):format(python, path.concat { ctx.package:get_install_path(), target })
            )
        end)
    end,
    ["pyvenv"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_pyvenv_exec_wrapper(bin, target)
        end)
    end,
    ["dotnet"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write dotnet wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            return ctx:write_shell_exec_wrapper(
                bin,
                ("dotnet %q"):format(path.concat {
                    ctx.package:get_install_path(),
                    target,
                })
            )
        end)
    end,
    ["node"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_node_exec_wrapper(bin, target)
        end)
    end,
    ["exec"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_exec_wrapper(bin, target)
        end)
    end,
    ["java-jar"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write Java JAR wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            return ctx:write_shell_exec_wrapper(
                bin,
                ("java -jar %q"):format(path.concat {
                    ctx.package:get_install_path(),
                    target,
                })
            )
        end)
    end,
    ["nuget"] = function(target)
        return require("mason-core.managers.v2.nuget").bin_path(target)
    end,
    ["npm"] = function(target)
        return require("mason-core.managers.v2.npm").bin_path(target)
    end,
    ["gem"] = function(target)
        return require("mason-core.managers.v2.gem").create_bin_wrapper(target)
    end,
    ["cargo"] = function(target)
        return require("mason-core.managers.v2.cargo").bin_path(target)
    end,
    ["pypi"] = function(target)
        return require("mason-core.managers.v2.pypi").bin_path(target)
    end,
    ["golang"] = function(target)
        return require("mason-core.managers.v2.golang").bin_path(target)
    end,
}

---@async
---@param ctx InstallContext
---@param target string
local function chmod_exec(ctx, target)
    local bit = require "bit"
    -- see chmod(2)
    local USR_EXEC = 0x40
    local GRP_EXEC = 0x8
    local ALL_EXEC = 0x1
    local EXEC = bit.bor(USR_EXEC, GRP_EXEC, ALL_EXEC)
    local fstat = ctx.fs:fstat(target)
    if bit.band(fstat.mode, EXEC) ~= EXEC then
        local plus_exec = bit.bor(fstat.mode, EXEC)
        log.fmt_debug("Setting exec flags on file %s %o -> %o", target, fstat.mode, plus_exec)
        ctx.fs:chmod(target, plus_exec) -- chmod +x
    end
end

---@async
---@param ctx InstallContext
---@param purl Purl
---@param source PackageSource
function M.link(ctx, purl, source)
    return Result.try(function(try)
        if not ctx.package.spec.bin then
            log.fmt_debug("%s spec provides no bin.", ctx.package)
            return
        end
        local expr_ctx = { version = purl.version, source = source }
        for bin, raw_target in pairs(ctx.package.spec.bin) do
            local target = try(expr.eval(raw_target, expr_ctx))

            -- Expand "npm:typescript-language-server"-like expressions
            local delegated_bin = _.match("^(.+):(.+)$", target)
            if #delegated_bin > 0 then
                local bin_type, executable = unpack(delegated_bin)
                log.fmt_trace("Transforming managed executable=%s via %s", executable, bin_type)
                local delegate =
                    try(Optional.of_nilable(delegates[bin_type]):ok_or(("Unknown bin type: %s"):format(bin_type)))
                target = try(delegate(executable, bin))
            end

            log.fmt_debug("Attempting to link %s -> %s (raw=%s)", bin, target, raw_target)
            if not ctx.fs:file_exists(target) then
                return Result.failure(("Tried to link bin %q to non-existent target %q."):format(bin, target))
            end

            if platform.is.unix then
                chmod_exec(ctx, target)
            end

            ctx:link_bin(bin, target)
        end
    end)
end

return M
