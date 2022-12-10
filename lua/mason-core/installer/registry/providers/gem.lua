local Result = require "mason-core.result"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(spec, purl, opts)
    ---@class GemSource : PackageSource
    local source = {
        package = purl.name,
        version = purl.version,
        extra_packages = spec.source.extra_packages,
    }
    return Result.success(source)
end

---@async
---@parma ctx InstallContext
---@param source GemSource
function M.install(ctx, source)
    local gem = require "mason-core.managers.v2.gem"
    return gem.install(source.package, source.version, {
        extra_packages = source.extra_packages,
    })
end

return M
