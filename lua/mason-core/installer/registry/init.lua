local a = require "mason-core.async"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local Purl = require "mason-core.purl"
local Optional = require "mason-core.optional"
local bin = require "mason-core.installer.registry.bin"
local log = require "mason-core.log"

local M = {}

local SOURCES = {
    ["cargo"] = "mason-core.installer.registry.providers.cargo",
    ["gem"] = "mason-core.installer.registry.providers.gem",
    ["generic"] = "mason-core.installer.registry.providers.generic",
    ["github"] = "mason-core.installer.registry.providers.github",
    ["golang"] = "mason-core.installer.registry.providers.golang",
    ["npm"] = "mason-core.installer.registry.providers.npm",
    ["nuget"] = "mason-core.installer.registry.providers.nuget",
    ["pypi"] = "mason-core.installer.registry.providers.pypi",
}

---@param purl Purl
local function get_provider(purl)
    return Optional.of_nilable(SOURCES[purl.type]):map(require):ok_or(("Unknown purl type: %s"):format(purl.type))
end

---@class SourceProvider
---@field parse fun(spec: RegistryPackageSpec, purl: Purl, opts: PackageInstallOpts): Result
---@field install async fun(ctx: InstallContext, source: PackageSource): Result

---@class PackageSource

---@param spec RegistryPackageSpec
---@param opts PackageInstallOpts
function M.parse(spec, opts)
    log.debug("Parsing package spec.", spec.name, opts)
    return Result.try(function(try)
        ---@type Purl
        local purl = try(Purl.parse(spec.source.id))
        log.debug("Parsed purl.", spec.source.id, purl)
        if opts.version then
            purl.version = opts.version
        end

        ---@type SourceProvider
        local provider = try(get_provider(purl))
        log.debug("Found provider for purl.", spec.source.id, provider)
        local source = try(provider.parse(spec, purl, opts))
        log.debug("Parsed source for purl.", spec.source.id, source)
        return {
            provider = provider,
            source = source,
            purl = purl,
        }
    end)
end

---@async
---@param spec RegistryPackageSpec
---@param opts PackageInstallOpts
function M.compile(spec, opts)
    log.debug("Compiling installer.", spec.name)
    return Result.try(function(try)
        if vim.in_fast_event() then
            -- parse implementations run synchronously and may access API functions
            a.scheduler()
        end
        ---@type { purl: Purl, provider: SourceProvider, source: PackageSource }
        local parsed = try(M.parse(spec, opts))

        ---@async
        ---@param ctx InstallContext
        return function(ctx)
            return Result.try(function(try)
                try(parsed.provider.install(ctx, parsed.source))
                try(bin.link(ctx, parsed.purl, parsed.source))
                ctx.receipt:with_primary_source {
                    type = ctx.package.spec.schema,
                    id = Purl.compile(parsed.purl),
                    metadata = parsed.source,
                }
            end):on_failure(function(err)
                error(err, 0)
            end)
        end
    end)
end

return M
