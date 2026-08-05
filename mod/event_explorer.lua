-- Explorateur en lecture seule de tous les evenements Factorio (defines.events)
-- et de tous les types d'alerte (defines.alert_type), categorises
-- heuristiquement et filtrables par recherche. Sert a REPERER quels
-- evenements pourraient valoir la peine d'etre cables au bridge Chroma dans
-- une prochaine iteration -- ca n'assigne pas d'effet directement, parce que
-- chaque evenement a une charge utile differente (voir control.lua : chacun
-- des 6 evenements geres a son propre gestionnaire sur-mesure).

local explorer = {}

local CATEGORY_RULES = {
  {pattern = "research", category = "Recherche"},
  {pattern = "technology", category = "Recherche"},
  {pattern = "train", category = "Trains"},
  {pattern = "rail", category = "Trains"},
  {pattern = "robot", category = "Robots"},
  {pattern = "construction", category = "Robots"},
  {pattern = "logistic", category = "Logistique"},
  {pattern = "storage", category = "Logistique"},
  {pattern = "repair", category = "Combat"},
  {pattern = "rocket", category = "Espace"},
  {pattern = "cargo", category = "Espace"},
  {pattern = "platform", category = "Espace"},
  {pattern = "space", category = "Espace"},
  {pattern = "gui", category = "Interface"},
  {pattern = "chart", category = "Interface"},
  {pattern = "cursor", category = "Interface"},
  {pattern = "selected", category = "Interface"},
  {pattern = "player", category = "Joueur"},
  {pattern = "damaged", category = "Combat"},
  {pattern = "died", category = "Combat"},
  {pattern = "die", category = "Combat"},
  {pattern = "turret", category = "Combat"},
  {pattern = "force", category = "Forces"},
  {pattern = "electric", category = "Reseau electrique"},
  {pattern = "fluid", category = "Reseau electrique"},
  {pattern = "pipeline", category = "Reseau electrique"},
  {pattern = "chunk", category = "Monde"},
  {pattern = "surface", category = "Monde"},
  {pattern = "tile", category = "Monde"},
  {pattern = "entity", category = "Entites"},
  {pattern = "built", category = "Entites"},
  {pattern = "mined", category = "Entites"},
}

local function categorize(name)
  for _, rule in ipairs(CATEGORY_RULES) do
    if name:find(rule.pattern, 1, true) then
      return rule.category
    end
  end
  return "Autre"
end

-- Nom defines.events -> cle interne utilisee dans mapping.json['events'].
-- Sert uniquement a marquer/relier les entrees deja cablees dans l'explorateur.
local WIRED_EVENT_NAMES = {
  on_research_finished = "research_finished",
  on_entity_damaged = "base_under_attack",
  on_rocket_launched = "rocket_launched",
  on_player_died = "player_died",
  on_train_changed_state = "train_arrived",
  on_player_crafted_item = "item_crafted",
}

function explorer.build_catalog()
  local catalog = {}

  for name, _ in pairs(defines.events) do
    table.insert(catalog, {
      kind = "event",
      name = name,
      category = categorize(name),
      wired_key = WIRED_EVENT_NAMES[name],
    })
  end

  for name, _ in pairs(defines.alert_type) do
    table.insert(catalog, {
      kind = "alert",
      name = name,
      category = categorize(name),
      wired_key = name, -- les alertes sont indexees par leur propre nom dans mapping.json['alerts']
    })
  end

  table.sort(catalog, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.name < b.name
  end)
  return catalog
end

-- Extrait le nom interne du mod (ex: "pyalienlife") d'un chemin d'icone
-- Factorio (toujours de la forme "__nom-du-mod__/graphics/..."), y compris
-- "base"/"core" pour le vanilla -- c'est la seule info fiable qu'on a a
-- l'execution pour retrouver le mod proprietaire d'un prototype (il n'existe
-- pas d'API directe "quel mod a ajoute cette entite").
function explorer.mod_of_icon(icon_path)
  if type(icon_path) ~= "string" then return "inconnu" end
  return icon_path:match("^__(.-)__") or "inconnu"
end

-- Fermeture nommee (definie une seule fois) plutot qu'une fonction anonyme
-- recreee a chaque appel de mod_of() : count_player_alerts (control.lua)
-- appelle mod_of() pour CHAQUE alerte active, potentiellement des dizaines
-- par seconde et par joueur sous attaque -- pas la peine d'allouer une
-- nouvelle closure a chaque fois.
local function _icon_of(obj)
  if not obj then return nil end
  if obj.icon then return obj.icon end
  if obj.icons and obj.icons[1] then return obj.icons[1].icon end
  return nil
end

-- Marche pour une entite, un prototype, une technologie, un item stack...
-- n'importe quel objet exposant .icon ou .icons (meme forme dans l'API
-- Factorio pour tous ces types). pcall : certains objets n'exposent pas ces
-- champs, ou sont invalides au moment de l'appel (entite detruite entre
-- l'evenement et la lecture par exemple).
function explorer.mod_of(obj)
  local ok, icon = pcall(_icon_of, obj)
  if not ok then return "inconnu" end
  return explorer.mod_of_icon(icon)
end

function explorer.categories(catalog)
  local seen = {}
  local list = {}
  for _, entry in ipairs(catalog) do
    if not seen[entry.category] then
      seen[entry.category] = true
      table.insert(list, entry.category)
    end
  end
  table.sort(list)
  table.insert(list, 1, "Toutes")
  return list
end

return explorer
