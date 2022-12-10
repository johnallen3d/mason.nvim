local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local platform = require "mason-core.platform"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    if spec.source.supported_platforms then
        if
            not _.any(function(target)
                return platform.is[target]
            end, spec.source.supported_platforms)
        then
            return Result.failure "PLATFORM_UNSUPPORTED"
        end
    end

    local repository_url = _.path({ "qualifiers", "repository_url" }, purl)

    local git
    if repository_url then
        git = {
            url = repository_url,
            rev = _.path({ "qualifiers", "rev" }, purl) == "true",
        }
    end

    ---@class CargoSource : PackageSource
    local source = {
        crate = purl.name,
        version = purl.version,
        features = _.path({ "qualifiers", "features" }, purl),--[[@as string?]]
        git = git,
    }
    return Result.success(source)
end

---@async
---@param cts InstallContext
---@param source CargoSource
function M.install(ctx, source)
    local cargo = require "mason-core.managers.v2.cargo"
    return cargo.install(source.crate, source.version, {
        git = source.git,
        features = source.features,
    })
end

return M
