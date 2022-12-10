local _ = require "mason-core.functional"
local Result = require "mason-core.result"
local expr = require "mason-core.installer.registry.expr"
local util = require "mason-core.installer.registry.util"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(spec, purl, opts)
    return Result.try(function(try)
        local download = try(util.coalesce_by_target(spec.source.download, opts):ok_or "PLATFORM_UNSUPPORTED")

        local expr_ctx = { version = purl.version }
        ---@type { files: table<string, string> }
        local interpolated_download = try(expr.tbl_interpolate(download, expr_ctx))

        ---@class GenericSource : PackageSource
        local source = {
            download = interpolated_download,
        }
        return source
    end)
end

---@async
---@param ctx InstallContext
---@param source GenericSource
function M.install(ctx, source)
    local std = require "mason-core.managers.v2.std"
    return Result.try(function(try)
        -- XXX: might want to parallelize downloads
        for out_file, url in pairs(source.download.files) do
            try(std.download_file(url, out_file))
            try(std.unpack(out_file))
        end
    end)
end

return M
