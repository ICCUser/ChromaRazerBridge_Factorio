-- Ecriture JSON partagee entre control.lua et gui.lua.

local util = {}

-- player_index optionnel : si fourni, Factorio n'ecrit CE fichier que sur la
-- machine de ce joueur precis (sous-dossier prive script-output/<index>/),
-- invisible pour tous les autres joueurs connectes. Omis (nil) : ecriture
-- partagee classique a la racine de script-output/, comme avant. index 0
-- n'existe pas et provoquait un echec silencieux de l'ecriture -- on ne le
-- transmet donc que s'il est strictement positif.
function util.safe_write_json(filename, tbl, append, player_index)
  local ok, encoded = pcall(helpers.table_to_json, tbl)
  if not ok then
    log("[chroma-bridge] table_to_json a echoue pour " .. filename .. ": " .. tostring(encoded))
    return
  end
  local write_ok, write_err
  if player_index and player_index > 0 then
    write_ok, write_err = pcall(helpers.write_file, filename, encoded .. "\n", append or false, player_index)
  else
    write_ok, write_err = pcall(helpers.write_file, filename, encoded .. "\n", append or false)
  end
  if not write_ok then
    log("[chroma-bridge] write_file a echoue pour " .. filename .. ": " .. tostring(write_err))
  end
end

-- Vide un fichier (utilise pour chroma_events.jsonl en debut de session, voir
-- control.lua) : contrairement a safe_write_json, n'ecrit aucun JSON, juste
-- une chaine vide en mode non-append -- Factorio n'expose pas de "supprimer
-- un fichier", ecraser avec un contenu vide est le seul moyen de repartir
-- propre.
function util.reset_file(filename, player_index)
  if player_index and player_index > 0 then
    pcall(helpers.write_file, filename, "", false, player_index)
  else
    pcall(helpers.write_file, filename, "", false)
  end
end

return util
