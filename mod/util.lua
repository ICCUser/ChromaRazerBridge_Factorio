-- Ecriture JSON partagee entre control.lua et gui.lua.

local util = {}

function util.safe_write_json(filename, tbl, append)
  local ok, encoded = pcall(helpers.table_to_json, tbl)
  if not ok then
    log("[chroma-bridge] table_to_json a echoue pour " .. filename .. ": " .. tostring(encoded))
    return
  end
  -- Pas de player_index ici : on veut ecrire dans script-output/ commun,
  -- pas dans le sous-dossier d'un joueur precis (index 0 n'existe pas et
  -- provoquait un echec silencieux de l'ecriture).
  local write_ok, write_err = pcall(helpers.write_file, filename, encoded .. "\n", append or false)
  if not write_ok then
    log("[chroma-bridge] write_file a echoue pour " .. filename .. ": " .. tostring(write_err))
  end
end

return util
