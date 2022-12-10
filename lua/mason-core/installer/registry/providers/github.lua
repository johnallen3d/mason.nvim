local a = require "mason-core.async"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local platform = require "mason-core.platform"
local settings = require "mason.settings"
local expr = require "mason-core.installer.registry.expr"
local util = require "mason-core.installer.registry.util"
local path = require "mason-core.path"

local build = {
    ---@param spec RegistryPackageSpec
    ---@param purl Purl
    ---@param opts PackageInstallOpts
    parse = function(spec, purl, opts)
        return Result.try(function(try)
            ---@type { run: string }
            local build_instruction = try(util.coalesce_by_target(spec.source.build, opts):ok_or "PLATFORM_UNSUPPORTED")

            ---@class GitHubBuildSource : PackageSource
            local source = {
                build = build_instruction,
                repo = ("https://github.com/%s/%s.git"):format(purl.namespace, purl.name),
                rev = purl.version,
            }
            return source
        end)
    end,

    ---@async
    ---@param ctx InstallContext
    ---@param source GitHubBuildSource
    install = function(ctx, source)
        local std = require "mason-core.managers.v2.std"
        return Result.try(function(try)
            try(std.clone(source.repo, { rev = source.rev }))
            try(platform.when {
                unix = function()
                    return ctx.spawn.bash {
                        on_spawn = a.scope(function(_, stdio)
                            local stdin = stdio[1]
                            local write = a.promisify(vim.loop.write)
                            write(stdin, "set -euxo pipefail;\n")
                            write(stdin, source.build.run)
                            stdin:shutdown()
                        end),
                    }
                end,
                win = function()
                    local powershell = require "mason-core.managers.powershell"
                    return powershell.script(source.build.run, {}, ctx.spawn)
                end,
            })
        end)
    end,
}

local release = {
    ---@param spec RegistryPackageSpec
    ---@param purl Purl
    ---@param opts PackageInstallOpts
    parse = function(spec, purl, opts)
        return Result.try(function(try)
            local asset = try(util.coalesce_by_target(spec.source.asset, opts):ok_or "PLATFORM_UNSUPPORTED")

            local expr_ctx = { version = purl.version }
            local asset_file_components = _.split(":", asset.file)
            local source_file = try(expr.eval(_.head(asset_file_components), expr_ctx))
            local out_file = try(expr.eval(_.last(asset_file_components), expr_ctx))

            if _.matches("/$", out_file) then
                -- out_file is a dir expression (e.g. "libexec/")
                out_file = path.concat { out_file, source_file }
            end

            local interpolated_asset = try(expr.tbl_interpolate(asset, expr_ctx))

            ---@class GitHubReleaseSource : PackageSource
            local source = {
                asset = interpolated_asset,
                out_file = out_file,
                asset_file_download_url = settings.current.github.download_url_template:format(
                    ("%s/%s"):format(purl.namespace, purl.name),
                    purl.version,
                    source_file
                ),
            }
            return source
        end)
    end,

    ---@async
    ---@param ctx InstallContext
    ---@param source GitHubReleaseSource
    install = function(ctx, source)
        local std = require "mason-core.managers.v2.std"
        return Result.try(function(try)
            local out_dir = vim.fn.fnamemodify(source.out_file, ":h")
            local out_file = vim.fn.fnamemodify(source.out_file, ":t")
            if out_dir ~= "." then
                try(Result.pcall(function()
                    ctx.fs:mkdir(out_dir)
                end))
            end
            try(ctx:chdir(out_dir, function()
                return Result.try(function(try)
                    try(std.download_file(source.asset_file_download_url, out_file))
                    try(std.unpack(out_file))
                end)
            end))
        end)
    end,
}

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(spec, purl, opts)
    if spec.source.asset then
        return release.parse(spec, purl, opts)
    elseif spec.source.build then
        return build.parse(spec, purl, opts)
    else
        return Result.failure "Unknown source type."
    end
end

---@async
---@param ctx InstallContext
---@param source GitHubReleaseSource | GitHubBuildSource
function M.install(ctx, source)
    if source.asset then
        return release.install(ctx, source)
    elseif source.build then
        return build.install(ctx, source)
    else
        return Result.failure "Unknown source type."
    end
end

return M
