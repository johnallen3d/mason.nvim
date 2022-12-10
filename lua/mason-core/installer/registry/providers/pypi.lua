local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local settings = require "mason.settings"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class PypiSource : PackageSource
    local source = {
        package = purl.name,
        version = purl.version,
        extra_packages = spec.source.extra_packages,
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source PypiSource
function M.install(ctx, source)
    local pypi = require "mason-core.managers.v2.pypi"
    return Result.try(function(try)
        try(pypi.init {
            upgrade_pip = settings.current.pip.upgrade_pip,
        })
        try(pypi.install(source.package, source.version, {
            extra_packages = source.extra_packages,
        }))
    end)
end

return M
