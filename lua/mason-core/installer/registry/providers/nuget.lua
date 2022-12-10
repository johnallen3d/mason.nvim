local Result = require "mason-core.result"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class NugetSource : PackageSource
    local source = {
        package = purl.name,
        version = purl.version,
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source NugetSource
function M.install(ctx, source)
    local nuget = require "mason-core.managers.v2.nuget"
    return nuget.install(source.package, source.version)
end

return M
