local _ = require "mason-core.functional"
local Optional = require "mason-core.optional"
local platform = require "mason-core.platform"

local M = {}

---@generic T : { target: string|string[] }
---@param candidates T[] | T
---@param opts PackageInstallOpts
---@return Optional # Optional<T>
function M.coalesce_by_target(candidates, opts)
    if not vim.tbl_islist(candidates) then
        return Optional.of(candidates)
    end
    return Optional.of_nilable(_.find_first(function(asset)
        if opts.target then
            -- Matching against a provided target rather than the current platform is an escape hatch primarily meant
            -- for automated testing purposes.
            if type(asset.target) == "table" then
                return _.any(_.equals(opts.target), asset.target)
            else
                return asset.target == opts.target
            end
        else
            if type(asset.target) == "table" then
                return _.any(function(target)
                    return platform.is[target]
                end, asset.target)
            else
                return platform.is[asset.target]
            end
        end
    end, candidates))
end

return M
