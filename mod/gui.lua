-- Interface en jeu (CONTROL+SHIFT+C) pour configurer, sans quitter Factorio,
-- quel appareil / quelle touche / quelle couleur / quel clignotement est
-- associe a chaque evenement ponctuel ou alerte continue du bridge.
--
-- Le resultat est ecrit dans script-output/chroma_mapping.json, relu et
-- fusionne automatiquement par le bridge Python (mapping_loader.py) sans
-- avoir besoin de relancer main.py.

local util = require("util")
local event_explorer = require("event_explorer")
local keyboard_layout_data = require("keyboard_layout_data")

local gui = {}

-- Catalogue complet defines.events/defines.alert_type : statique pour toute
-- la session de jeu, pas la peine de le recalculer a chaque ouverture.
local _catalog_cache = nil

local KEY_BUTTON_SIZE = 28

local function player_mapping(player)
  storage.player_mappings = storage.player_mappings or {}
  return storage.player_mappings[player.name]
end

-- Expose au control.lua (count_custom_alert_watches) sans dupliquer l'acces
-- a storage.player_mappings.
function gui.player_mapping(player)
  return player_mapping(player)
end

local function current_layout_name(player)
  local mapping = player_mapping(player)
  return (mapping and mapping.layout == "qwerty_us") and "qwerty_us" or "azerty_fr"
end

-- (ligne, colonne) -> nom de touche, pour le layout donne. Recalcule a
-- chaque appel (pas cher : ~100 entrees, appele seulement a l'ouverture du
-- clavier virtuel ou au clic sur une touche, pas a chaque tick).
local function inverse_layout(layout_name)
  local layout = keyboard_layout_data[layout_name] or keyboard_layout_data.qwerty_us
  local by_pos = {}
  for label, pos in pairs(layout) do
    by_pos[pos[1] .. ":" .. pos[2]] = label
  end
  return by_pos
end

local DEVICES = {
  {key = "all", label = "Tous les peripheriques"},
  {key = "keyboard", label = "Clavier"},
  {key = "mouse", label = "Souris"},
  {key = "mousepad", label = "Tapis de souris"},
  {key = "headset", label = "Casque"},
  {key = "chromalink", label = "ChromaLink (= ton tapis, apparemment !)"},
}

local ZONES = {
  {key = "all", label = "Tout le clavier"},
  {key = "zone:function_row", label = "Barre de fonction (F1-F12)"},
  {key = "zone:movement", label = "Deplacement (ZQSD/WASD)"},
  {key = "zone:arrows", label = "Fleches directionnelles"},
  {key = "zone:digits_row", label = "Rangee de chiffres"},
  {key = "__custom__", label = "Touche precise (texte)..."},
  {key = "__keyboard_picker__", label = "Clavier visuel (plusieurs touches)..."},
}

local COLOR_PRESETS = {
  {255, 0, 0}, {255, 120, 0}, {255, 200, 0}, {0, 255, 60}, {0, 200, 120},
  {0, 180, 255}, {60, 60, 255}, {160, 0, 255}, {255, 0, 180}, {255, 255, 255},
}

local ITEMS = {
  {section = "events", key = "research_finished", label = "Recherche terminee"},
  {section = "events", key = "base_under_attack", label = "Base attaquee"},
  {section = "events", key = "rocket_launched", label = "Fusee lancee"},
  {section = "events", key = "player_died", label = "Joueur mort"},
  {section = "events", key = "train_arrived", label = "Train arrive a quai"},
  {section = "events", key = "item_crafted", label = "Objet fabrique"},
  {section = "alerts", key = "entity_under_attack", label = "[Alerte] Entite attaquee"},
  {section = "alerts", key = "turret_fire", label = "[Alerte] Tourelle en action"},
  {section = "alerts", key = "no_power", label = "[Alerte] Coupure de courant (autour de toi)"},
  {section = "alerts", key = "low_power", label = "[Alerte] Sous-alimentation electrique (autour de toi)"},
  {section = "alerts", key = "train_out_of_fuel", label = "[Alerte] Train sans carburant"},
  {section = "alerts", key = "train_no_path", label = "[Alerte] Train sans chemin"},
  {section = "alerts", key = "not_enough_repair_packs", label = "[Alerte] Manque de kits de reparation"},
  {section = "alerts", key = "no_material_for_construction", label = "[Alerte] Manque de materiaux"},
  {section = "alerts", key = "not_enough_construction_robots", label = "[Alerte] Manque de robots de construction"},
  {section = "alerts", key = "no_storage", label = "[Alerte] Stockage plein"},
  {section = "alerts", key = "train_nearby", label = "[Alerte] Train en mouvement a proximite (danger)"},
}

local DEFAULT_MAPPING = {
  layout = "azerty_fr",
  keyboard_idle = {
    color1 = {230, 100, 20},
    color2 = {20, 10, 0},
  },
  research_bar = {
    enabled = true,
    keys = {"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"},
    color_bar = {0, 255, 60},
    color_empty = {20, 20, 20},
  },
  health_bar = {
    enabled = true,
    keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"},
    color_bar = {0, 255, 0},
    color_empty = {40, 0, 0},
  },
  events = {
    research_finished = {device = "all", color = {0, 255, 60}, blink = true, blink_interval = 0.2, hold = 3.0},
    base_under_attack = {device = "all", color = {255, 0, 0}, blink = false, hold = 3.0},
    rocket_launched = {device = "all", style = "spectrum", hold = 4.0},
    player_died = {device = "all", color = {120, 0, 0}, blink = false, hold = 3.0},
    train_arrived = {device = "keyboard", scope = "zone:arrows", color = {0, 180, 255}, blink = false, hold = 2.0},
    item_crafted = {device = "keyboard", scope = "zone:movement", color = {80, 200, 80}, blink = false, hold = 0.4},
  },
  alerts = {
    entity_under_attack = {device = "all", color = {255, 0, 0}, blink = false, priority = 10},
    turret_fire = {device = "all", color = {255, 0, 0}, blink = false, priority = 10},
    no_power = {device = "keyboard", scope = "zone:movement", color = {255, 0, 255}, blink = true, blink_interval = 0.4, priority = 9},
    low_power = {device = "keyboard", scope = "zone:movement", color = {255, 140, 0}, blink = false, priority = 6},
    train_out_of_fuel = {device = "keyboard", scope = "zone:arrows", color = {255, 140, 0}, blink = false, priority = 8},
    train_no_path = {device = "keyboard", scope = "zone:arrows", color = {255, 60, 0}, blink = true, blink_interval = 0.5, priority = 8},
    not_enough_repair_packs = {device = "keyboard", scope = "zone:movement", color = {255, 200, 0}, blink = false, priority = 5},
    no_material_for_construction = {device = "keyboard", scope = "zone:movement", color = {255, 200, 0}, blink = false, priority = 5},
    not_enough_construction_robots = {device = "keyboard", scope = "zone:movement", color = {255, 200, 0}, blink = false, priority = 5},
    no_storage = {device = "keyboard", scope = "zone:movement", color = {255, 200, 0}, blink = false, priority = 5},
    train_nearby = {device = "all", color = {255, 0, 0}, blink = true, blink_interval = 0.2, priority = 9},
  },
}

local function deep_copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Ecrit chroma_mapping.json en ciblant player.index : Factorio n'envoie ce
-- fichier QUE sur la machine de ce joueur precis (sous-dossier prive), donc
-- la config d'un joueur n'apparait jamais chez les autres. Voir
-- util.safe_write_json.
local function write_mapping_file(player)
  local cfg = player_mapping(player)
  if cfg then
    util.safe_write_json("chroma_mapping.json", cfg, false, player.index)
  end
end

-- Reecrit chroma_mapping.json de maniere inconditionnelle, pour chaque
-- joueur connecte. Un mod Lua ne peut pas verifier si un fichier existe deja
-- sur le disque (sandbox de Factorio), donc on ne peut pas detecter qu'il a
-- disparu -- on se contente de le reecrire regulierement (control.lua
-- l'appelle depuis write_status, ~1x/seconde) pour s'auto-reparer si jamais
-- le fichier est supprime/perdu (ex: script-output vide entre deux
-- sessions) sans que storage.player_mappings, lui, ne soit affecte (il est
-- sauvegarde avec la partie).
function gui.ensure_mapping_files()
  if not storage.player_mappings then return end
  for _, player in pairs(game.connected_players) do
    write_mapping_file(player)
  end
end

-- Cree/migre la config individuelle de chaque joueur connecte. Si une
-- ancienne config partagee existe (storage.mapping, d'avant le passage a
-- une config par joueur), elle sert de point de depart -- personne ne perd
-- ses reglages actuels au moment de la migration.
function gui.init_defaults()
  storage.player_mappings = storage.player_mappings or {}
  local legacy_shared = storage.mapping

  for _, player in pairs(game.connected_players) do
    if not storage.player_mappings[player.name] then
      storage.player_mappings[player.name] = deep_copy(legacy_shared or DEFAULT_MAPPING)
    end
    local pm = storage.player_mappings[player.name]
    -- migrations : parties commencees avant l'ajout de ces champs.
    for _, bar in ipairs({"research_bar", "health_bar", "keyboard_idle"}) do
      if not pm[bar] then
        pm[bar] = deep_copy(DEFAULT_MAPPING[bar])
      end
    end
    pm.alerts = pm.alerts or {}
    for name, cfg in pairs(DEFAULT_MAPPING.alerts) do
      if not pm.alerts[name] then
        pm.alerts[name] = deep_copy(cfg)
      end
    end
    pm.custom_alert_watches = pm.custom_alert_watches or {}
    pm.next_watch_id = pm.next_watch_id or 1
  end

  storage.mapping = nil -- migre vers storage.player_mappings, plus utilise
  storage.chroma_draft = storage.chroma_draft or {}
end

local function find_item(player, section, key)
  for _, item in ipairs(ITEMS) do
    if item.section == section and item.key == key then return item end
  end
  -- Pas dans la liste statique : c'est peut-etre une alerte personnalisee
  -- (haut-parleur) ajoutee par ce joueur -- son libelle vit dans
  -- custom_alert_watches, pas dans ITEMS.
  if section == "alerts" and key:match("^custom_") then
    local mapping = player_mapping(player)
    local watches = mapping and mapping.custom_alert_watches
    if watches then
      for _, watch in ipairs(watches) do
        if "custom_" .. watch.id == key then
          local label = (watch.label ~= "" and watch.label) or watch.match_text
          return {section = "alerts", key = key, label = "[Alerte perso] " .. label}
        end
      end
    end
  end
  return nil
end

local function device_index_of(device_key)
  for i, d in ipairs(DEVICES) do
    if d.key == device_key then return i end
  end
  return 1
end

local function device_labels()
  local labels = {}
  for i, d in ipairs(DEVICES) do labels[i] = d.label end
  return labels
end

local function is_known_zone(scope)
  if type(scope) == "table" then return false end
  for _, z in ipairs(ZONES) do
    if z.key ~= "__custom__" and z.key ~= "__keyboard_picker__" and z.key == scope then return true end
  end
  return false
end

local function zone_key_index(key)
  for i, z in ipairs(ZONES) do
    if z.key == key then return i end
  end
  return 1
end

local function zone_index_of(scope)
  if type(scope) == "table" then
    return zone_key_index("__keyboard_picker__")
  end
  if is_known_zone(scope) then
    return zone_key_index(scope)
  end
  return zone_key_index("__custom__")
end

local function zone_labels()
  local labels = {}
  for i, z in ipairs(ZONES) do labels[i] = z.label end
  return labels
end

local function select_item(player, section, key)
  local mapping = player_mapping(player)
  local existing = mapping and mapping[section] and mapping[section][key]
  local cfg = existing and deep_copy(existing) or {device = "all", color = {255, 255, 255}, blink = false, blink_interval = 0.3}
  if cfg.enabled == nil then cfg.enabled = true end
  if section == "events" and cfg.hold == nil then cfg.hold = 2.0 end
  if section == "alerts" and cfg.priority == nil then cfg.priority = 5 end
  storage.chroma_draft[player.index] = {section = section, key = key, cfg = cfg}
end

-- Rich text Factorio ([color=r,g,b]...[/color]) plutot qu'un tint sur
-- sprite-button : plus fiable, et evite les soucis de rendu (icone blanche,
-- bouton grise) rencontres avec le tint sur cette version du jeu.
local function color_swatch_caption(color, block_count)
  local r = math.floor(color[1] or 255)
  local g = math.floor(color[2] or 255)
  local b = math.floor(color[3] or 255)
  return "[color=" .. r .. "," .. g .. "," .. b .. "]" .. string.rep("■", block_count or 3) .. "[/color]"
end

local function set_visible(element, visible)
  if element and element.valid then element.visible = visible end
end

local function build_list(parent, player)
  parent.clear()
  local current_section = nil
  for _, item in ipairs(ITEMS) do
    if item.section ~= current_section then
      current_section = item.section
      parent.add{
        type = "label",
        caption = (current_section == "events") and "-- Evenements ponctuels --" or "-- Alertes continues --",
      }
    end
    parent.add{
      type = "button",
      name = "chroma_select__" .. item.section .. "__" .. item.key,
      caption = item.label,
    }
  end

  local mapping = player_mapping(player)
  local watches = mapping and mapping.custom_alert_watches
  if watches and #watches > 0 then
    parent.add{type = "label", caption = "-- Alertes personnalisees --"}
    for _, watch in ipairs(watches) do
      local label = (watch.label ~= "" and watch.label) or watch.match_text
      parent.add{
        type = "button",
        name = "chroma_select__alerts__custom_" .. watch.id,
        caption = "[Alerte perso] " .. label,
      }
    end
  end
end

local function build_detail(player)
  local window = player.gui.screen.chroma_bridge_window
  if not window then return end
  local detail = window.chroma_body.chroma_detail_flow
  detail.clear()

  local draft = storage.chroma_draft[player.index]
  if not draft then
    detail.add{type = "label", caption = "Selectionne un evenement ou une alerte a gauche."}
    return
  end

  local cfg = draft.cfg
  local item = find_item(player, draft.section, draft.key)

  detail.add{type = "label", caption = (item and item.label or draft.key)}

  detail.add{
    type = "checkbox", name = "chroma_enabled_checkbox",
    caption = "Actif (declenche cet event/cette alerte)", state = (cfg.enabled ~= false),
  }

  detail.add{type = "label", caption = "Peripherique :"}
  local device_dd = detail.add{type = "drop-down", name = "chroma_device_dropdown", items = device_labels()}
  device_dd.selected_index = device_index_of(cfg.device or "all")

  local style_checkbox = detail.add{
    type = "checkbox", name = "chroma_style_spectrum_checkbox",
    caption = "Effet arc-en-ciel (ignore la couleur choisie)", state = (cfg.style == "spectrum"),
  }
  set_visible(style_checkbox, cfg.device == "all")

  local scope_flow = detail.add{type = "flow", name = "chroma_scope_flow", direction = "vertical"}
  set_visible(scope_flow, cfg.device == "keyboard")
  scope_flow.add{type = "label", caption = "Zone du clavier :"}
  local scope = cfg.scope or "all"
  local is_group = (type(scope) == "table")
  local zone_dd = scope_flow.add{type = "drop-down", name = "chroma_zone_dropdown", items = zone_labels()}
  zone_dd.selected_index = zone_index_of(scope)

  local custom_field = scope_flow.add{
    type = "textfield", name = "chroma_custom_key_field",
    text = (not is_group and not is_known_zone(scope) and scope ~= "all") and scope or "",
  }
  custom_field.tooltip = "Nom de touche exact, ex: F5, SPACE, ENTER (voir print_mapping_table.py)"
  set_visible(custom_field, not is_group and not is_known_zone(scope))

  local group_flow = scope_flow.add{type = "flow", name = "chroma_group_flow", direction = "vertical"}
  set_visible(group_flow, is_group)
  local group_summary = is_group and (#scope > 0 and table.concat(scope, ", ") or "(aucune touche selectionnee)") or ""
  group_flow.add{type = "label", name = "chroma_group_summary_label", caption = "Touches choisies : " .. group_summary}
  group_flow.add{type = "button", name = "chroma_open_keyboard_picker_button", caption = "Ouvrir le clavier virtuel"}

  local color_flow = detail.add{type = "flow", name = "chroma_color_flow", direction = "vertical"}
  set_visible(color_flow, cfg.style ~= "spectrum")
  color_flow.add{type = "label", caption = "Couleur :"}
  local palette = color_flow.add{type = "table", name = "chroma_color_palette", column_count = 5}
  for i, preset in ipairs(COLOR_PRESETS) do
    palette.add{
      type = "button", name = "chroma_color_preset__" .. i,
      caption = color_swatch_caption(preset, 3),
      tooltip = "Choisir cette couleur",
    }
  end

  local color = cfg.color or {255, 255, 255}
  local rgb_flow = color_flow.add{type = "flow", name = "chroma_rgb_flow", direction = "horizontal"}
  local function channel_slider(label, name, value)
    rgb_flow.add{type = "label", caption = label}
    local s = rgb_flow.add{type = "slider", name = name, minimum_value = 0, maximum_value = 255, value = value}
    s.style.width = 100
  end
  channel_slider("R", "chroma_slider_r", color[1])
  channel_slider("G", "chroma_slider_g", color[2])
  channel_slider("B", "chroma_slider_b", color[3])
  rgb_flow.add{type = "label", name = "chroma_color_preview", caption = color_swatch_caption(color, 6), tooltip = "Apercu"}

  local blink_checkbox = detail.add{type = "checkbox", name = "chroma_blink_checkbox", caption = "Clignoter", state = cfg.blink or false}
  local blink_flow = detail.add{type = "flow", name = "chroma_blink_flow", direction = "horizontal"}
  set_visible(blink_flow, cfg.blink or false)
  blink_flow.add{type = "label", caption = "Delai (secondes) :"}
  local blink_interval = cfg.blink_interval or 0.3
  blink_flow.add{type = "slider", name = "chroma_blink_slider", minimum_value = 1, maximum_value = 20, value = math.floor(blink_interval * 10 + 0.5)}
  blink_flow.add{type = "label", name = "chroma_blink_value_label", caption = string.format("%.1fs", blink_interval)}

  if draft.section == "events" then
    detail.add{type = "label", caption = "Duree d'affichage apres l'evenement (secondes) :"}
    local hold_flow = detail.add{type = "flow", direction = "horizontal"}
    local hold = cfg.hold or 2.0
    hold_flow.add{type = "slider", name = "chroma_hold_slider", minimum_value = 1, maximum_value = 100, value = math.floor(hold * 10 + 0.5)}
    hold_flow.add{type = "label", name = "chroma_hold_value_label", caption = string.format("%.1fs", hold)}
  else
    detail.add{type = "label", caption = "Priorite (plus haut = passe devant les autres alertes) :"}
    local priority_flow = detail.add{type = "flow", direction = "horizontal"}
    priority_flow.add{type = "slider", name = "chroma_priority_slider", minimum_value = 0, maximum_value = 20, value = cfg.priority or 5}
    priority_flow.add{type = "label", name = "chroma_priority_value_label", caption = tostring(cfg.priority or 5)}
  end

  detail.add{type = "line"}
  detail.add{type = "button", name = "chroma_apply_button", caption = "Appliquer"}
end

-- --- Clavier virtuel (choix de plusieurs touches, DANS L'ORDRE du clic) ---
-- Utilise pour deux cibles differentes (storage.chroma_picker_target) :
--   "event_scope"   -> groupe personnalise pour l'event/alerte en cours d'edition (l'ordre n'a pas d'importance)
--   "research_bar"  -> sequence de la barre de recherche (l'ordre EST la progression 0% -> 100%)

local function picker_index_of(selection, label)
  for i, l in ipairs(selection) do
    if l == label then return i end
  end
  return nil
end

local function update_picker_summary(player)
  local window = player.gui.screen.chroma_keyboard_picker_window
  if not window then return end
  local selection = storage.chroma_picker_selection[player.index]
  window.chroma_picker_summary_label.caption = (#selection > 0)
    and ("Selection (" .. #selection .. ", dans l'ordre du clic) : " .. table.concat(selection, ", "))
    or "Aucune touche selectionnee."
end

local function build_keyboard_picker_grid(player)
  local window = player.gui.screen.chroma_keyboard_picker_window
  if not window then return end
  local grid = window.chroma_picker_grid
  grid.clear()

  local by_pos = inverse_layout(current_layout_name(player))
  local selection = storage.chroma_picker_selection[player.index]

  for row = 0, 5 do
    for col = 0, 21 do
      local label = by_pos[row .. ":" .. col]
      if label then
        local idx = picker_index_of(selection, label)
        local caption = idx and ("[color=0,255,120]" .. label .. " (" .. idx .. ")[/color]") or label
        local b = grid.add{type = "button", name = "chroma_picker_key__" .. row .. "__" .. col, caption = caption}
        b.style.size = {KEY_BUTTON_SIZE, KEY_BUTTON_SIZE}
        b.style.padding = 0
        b.style.font = "default-small"
      else
        local spacer = grid.add{type = "empty-widget"}
        spacer.style.size = {KEY_BUTTON_SIZE, KEY_BUTTON_SIZE}
      end
    end
  end
end

function gui.toggle_keyboard_picker(player, target)
  local screen = player.gui.screen
  if screen.chroma_keyboard_picker_window then
    screen.chroma_keyboard_picker_window.destroy()
    return
  end

  storage.chroma_picker_selection = storage.chroma_picker_selection or {}
  storage.chroma_picker_target = storage.chroma_picker_target or {}
  storage.chroma_picker_target[player.index] = target

  local initial = {}
  if target == "research_bar" or target == "health_bar" then
    local bar_draft = (target == "research_bar") and storage.chroma_research_draft[player.index] or storage.chroma_health_draft[player.index]
    if bar_draft and bar_draft.keys then
      for _, label in ipairs(bar_draft.keys) do table.insert(initial, label) end
    end
  else
    local draft = storage.chroma_draft[player.index]
    if draft and type(draft.cfg.scope) == "table" then
      for _, label in ipairs(draft.cfg.scope) do table.insert(initial, label) end
    end
  end
  storage.chroma_picker_selection[player.index] = initial

  local window = screen.add{
    type = "frame", name = "chroma_keyboard_picker_window", direction = "vertical",
    caption = "Clavier virtuel - choisis les touches",
  }
  window.auto_center = true

  local hint
  if target == "research_bar" then
    hint = "Clique les touches DANS L'ORDRE : la 1ere = 0% de recherche, la derniere = 100%. Reclique pour retirer."
  elseif target == "health_bar" then
    hint = "Clique les touches DANS L'ORDRE : la 1ere = 0% de vie, la derniere = 100%. Reclique pour retirer."
  else
    hint = "Clique les touches a inclure dans le groupe (elles passent en vert). Reclique pour retirer."
  end
  window.add{type = "label", caption = hint}

  local grid = window.add{type = "table", name = "chroma_picker_grid", column_count = 22}
  grid.style.horizontal_spacing = 2
  grid.style.vertical_spacing = 2

  window.add{type = "label", name = "chroma_picker_summary_label", caption = ""}

  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_picker_clear_button", caption = "Tout effacer"}
  bottom.add{type = "button", name = "chroma_picker_cancel_button", caption = "Annuler"}
  bottom.add{type = "button", name = "chroma_picker_confirm_button", caption = "Valider"}

  build_keyboard_picker_grid(player)
  update_picker_summary(player)
end

-- --- Editeur de la barre de recherche (touches ordonnees + couleurs) ---

local function add_color_picker_widgets(parent, prefix, color)
  local flow = parent.add{type = "flow", name = prefix .. "_flow", direction = "vertical"}
  local palette = flow.add{type = "table", name = prefix .. "_palette", column_count = 5}
  for i, preset in ipairs(COLOR_PRESETS) do
    palette.add{
      type = "button", name = prefix .. "_preset__" .. i,
      caption = color_swatch_caption(preset, 3), tooltip = "Choisir cette couleur",
    }
  end
  local rgb_flow = flow.add{type = "flow", name = prefix .. "_rgb_flow", direction = "horizontal"}
  local function channel_slider(label, chname, value)
    rgb_flow.add{type = "label", caption = label}
    local s = rgb_flow.add{type = "slider", name = chname, minimum_value = 0, maximum_value = 255, value = value}
    s.style.width = 100
  end
  channel_slider("R", prefix .. "_slider_r", color[1])
  channel_slider("G", prefix .. "_slider_g", color[2])
  channel_slider("B", prefix .. "_slider_b", color[3])
  rgb_flow.add{type = "label", name = prefix .. "_preview", caption = color_swatch_caption(color, 6)}
end

function build_research_bar_editor(player)
  local window = player.gui.screen.chroma_research_window
  if not window then return end
  window.clear()

  local draft = storage.chroma_research_draft[player.index]

  window.add{
    type = "checkbox", name = "chroma_rb_enabled_checkbox",
    caption = "Activer la barre de recherche", state = (draft.enabled ~= false),
  }

  window.add{type = "label", caption = "Touches, dans l'ordre (la premiere = 0% de recherche, la derniere = 100%) :"}
  local keys = draft.keys or {}
  window.add{
    type = "label", name = "chroma_rb_keys_summary_label",
    caption = (#keys > 0) and table.concat(keys, ", ") or "(aucune touche -- la barre ne s'affichera pas)",
  }
  window.add{type = "button", name = "chroma_rb_open_picker_button", caption = "Choisir les touches (clavier virtuel)"}

  window.add{type = "line"}
  window.add{type = "label", caption = "Couleur des touches deja atteintes par la progression :"}
  add_color_picker_widgets(window, "chroma_rb_bar", draft.color_bar or {0, 255, 60})

  window.add{type = "label", caption = "Couleur des touches pas encore atteintes :"}
  add_color_picker_widgets(window, "chroma_rb_empty", draft.color_empty or {20, 20, 20})

  window.add{type = "line"}
  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_rb_apply_button", caption = "Appliquer"}
  bottom.add{type = "button", name = "chroma_rb_close_button", caption = "Fermer"}
end

function gui.toggle_research_bar_editor(player)
  local screen = player.gui.screen
  if screen.chroma_research_window then
    screen.chroma_research_window.destroy()
    return
  end

  storage.chroma_research_draft = storage.chroma_research_draft or {}
  storage.chroma_research_draft[player.index] = deep_copy(player_mapping(player).research_bar)

  local window = screen.add{
    type = "frame", name = "chroma_research_window", direction = "vertical",
    caption = "Chroma Bridge - Barre de recherche",
  }
  window.auto_center = true

  build_research_bar_editor(player)
end

-- --- Editeur de la barre de vie (touches ordonnees + couleurs) ---
-- Meme principe que la barre de recherche, dupplique plutot que factorise
-- pour eviter de fragiliser le code deja teste de l'editeur de recherche.

function build_health_bar_editor(player)
  local window = player.gui.screen.chroma_health_window
  if not window then return end
  window.clear()

  local draft = storage.chroma_health_draft[player.index]

  window.add{
    type = "checkbox", name = "chroma_hb_enabled_checkbox",
    caption = "Activer la barre de vie", state = (draft.enabled ~= false),
  }

  window.add{type = "label", caption = "Touches, dans l'ordre (la premiere = 0% de vie, la derniere = 100%) :"}
  local keys = draft.keys or {}
  window.add{
    type = "label", name = "chroma_hb_keys_summary_label",
    caption = (#keys > 0) and table.concat(keys, ", ") or "(aucune touche -- la barre ne s'affichera pas)",
  }
  window.add{type = "button", name = "chroma_hb_open_picker_button", caption = "Choisir les touches (clavier virtuel)"}

  window.add{type = "line"}
  window.add{type = "label", caption = "Couleur des touches representant la vie restante :"}
  add_color_picker_widgets(window, "chroma_hb_bar", draft.color_bar or {0, 255, 0})

  window.add{type = "label", caption = "Couleur des touches representant la vie perdue :"}
  add_color_picker_widgets(window, "chroma_hb_empty", draft.color_empty or {40, 0, 0})

  window.add{type = "line"}
  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_hb_apply_button", caption = "Appliquer"}
  bottom.add{type = "button", name = "chroma_hb_close_button", caption = "Fermer"}
end

function gui.toggle_health_bar_editor(player)
  local screen = player.gui.screen
  if screen.chroma_health_window then
    screen.chroma_health_window.destroy()
    return
  end

  storage.chroma_health_draft = storage.chroma_health_draft or {}
  storage.chroma_health_draft[player.index] = deep_copy(player_mapping(player).health_bar)

  local window = screen.add{
    type = "frame", name = "chroma_health_window", direction = "vertical",
    caption = "Chroma Bridge - Barre de vie",
  }
  window.auto_center = true

  build_health_bar_editor(player)
end

-- --- Editeur de la couleur par defaut du clavier (keyboard_idle) ---
-- Couleur affichee sur TOUTES les touches quand rien d'autre n'est actif
-- (pas de recherche, pas de barre de vie, pas d'alerte clavier).

function build_default_color_editor(player)
  local window = player.gui.screen.chroma_default_window
  if not window then return end
  window.clear()

  local draft = storage.chroma_default_draft[player.index]

  window.add{type = "label", caption = "Couleur du clavier, de la souris et du tapis quand rien d'autre n'est actif :"}
  add_color_picker_widgets(window, "chroma_kd_c1", draft.color1 or {230, 100, 20})

  window.add{type = "label", caption = "Deuxieme couleur (respiration, fondu vers celle-ci) :"}
  add_color_picker_widgets(window, "chroma_kd_c2", draft.color2 or {20, 10, 0})

  window.add{type = "line"}
  window.add{
    type = "checkbox", name = "chroma_kd_ambient_checkbox",
    caption = "Reactif a l'etat de la partie (evolution des biters, pollution, jour/nuit)",
    state = draft.ambient_reactive or false,
  }
  window.add{
    type = "label",
    caption = "[color=150,150,150]Si coche, les deux couleurs ci-dessus sont ignorees : le clavier suit"
      .. " automatiquement l'ambiance (rouge si evolution elevee, jaune si pollution forte, bleu la nuit...).[/color]",
  }

  window.add{type = "line"}
  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_kd_apply_button", caption = "Appliquer"}
  bottom.add{type = "button", name = "chroma_kd_close_button", caption = "Fermer"}
end

function gui.toggle_default_color_editor(player)
  local screen = player.gui.screen
  if screen.chroma_default_window then
    screen.chroma_default_window.destroy()
    return
  end

  storage.chroma_default_draft = storage.chroma_default_draft or {}
  local draft = deep_copy(player_mapping(player).keyboard_idle)
  if draft.ambient_reactive == nil then draft.ambient_reactive = false end
  storage.chroma_default_draft[player.index] = draft

  local window = screen.add{
    type = "frame", name = "chroma_default_window", direction = "vertical",
    caption = "Chroma Bridge - Couleur par defaut du clavier",
  }
  window.auto_center = true

  build_default_color_editor(player)
end

-- --- Explorateur d'evenements (lecture seule) ---

local function is_wired(entry, player)
  if entry.kind == "event" then
    return entry.wired_key ~= nil
  end
  local mapping = player_mapping(player)
  return mapping and mapping.alerts[entry.name] ~= nil
end

-- Ventilation "vu depuis : base x12, pyalienlife x5" pour un event/alerte
-- deja survenu cette partie -- lu en direct dans storage.chroma_mod_counts
-- (alimente par control.lua) a chaque (re)construction de la liste, PAS
-- fige dans _catalog_cache (qui lui reste statique, base sur defines.*).
local function format_mod_counts(key)
  local counts = key and storage.chroma_mod_counts and storage.chroma_mod_counts[key]
  if not counts then return "" end
  local parts = {}
  for mod_name, n in pairs(counts) do
    table.insert(parts, mod_name .. " x" .. n)
  end
  if #parts == 0 then return "" end
  table.sort(parts)
  return "  [color=150,150,150](vu depuis : " .. table.concat(parts, ", ") .. ")[/color]"
end

local function matches_explorer_filter(entry, search, category)
  if category ~= "Toutes" and entry.category ~= category then return false end
  if search ~= "" and not entry.name:lower():find(search:lower(), 1, true) then return false end
  return true
end

local function build_explorer_list(player)
  local window = player.gui.screen.chroma_explorer_window
  if not window then return end
  local list = window.chroma_explorer_list
  list.clear()

  local state = storage.chroma_explorer_state[player.index]
  local shown = 0
  local MAX_SHOWN = 300 -- garde-fou anti-lag si la recherche est trop large

  for _, entry in ipairs(_catalog_cache) do
    if matches_explorer_filter(entry, state.search, state.category) then
      shown = shown + 1
      if shown <= MAX_SHOWN then
        local kind_label = (entry.kind == "event") and "[Event]" or "[Alerte]"
        local mod_counts_key = (entry.kind == "event") and entry.wired_key or entry.name
        local caption = kind_label .. " " .. entry.name .. "  (" .. entry.category .. ")" .. format_mod_counts(mod_counts_key)
        if is_wired(entry, player) then
          caption = "[color=0,255,120]OK[/color] " .. caption
          local wired_key = (entry.kind == "event") and entry.wired_key or entry.name
          list.add{
            type = "button", name = "chroma_explorer_goto__" .. entry.kind .. "__" .. wired_key,
            caption = caption, tooltip = "Ouvrir dans l'onglet Configuration",
          }
        else
          list.add{type = "label", caption = caption}
        end
      end
    end
  end

  local suffix = (shown > MAX_SHOWN) and (" (" .. MAX_SHOWN .. " premiers affiches, affine ta recherche)") or ""
  window.chroma_explorer_count_label.caption = shown .. " resultat(s)" .. suffix
end

function gui.toggle_explorer(player)
  local screen = player.gui.screen
  if screen.chroma_explorer_window then
    screen.chroma_explorer_window.destroy()
    return
  end

  if not _catalog_cache then
    _catalog_cache = event_explorer.build_catalog()
  end
  storage.chroma_explorer_state = storage.chroma_explorer_state or {}
  storage.chroma_explorer_state[player.index] = {search = "", category = "Toutes"}

  local window = screen.add{
    type = "frame", name = "chroma_explorer_window", direction = "vertical",
    caption = "Chroma Bridge - Explorateur d'evenements Factorio",
  }
  window.auto_center = true

  local filters = window.add{type = "flow", direction = "horizontal"}
  filters.add{type = "label", caption = "Recherche :"}
  filters.add{type = "textfield", name = "chroma_explorer_search"}
  filters.add{type = "label", caption = "Categorie :"}
  local cat_dd = filters.add{type = "drop-down", name = "chroma_explorer_category_dropdown", items = event_explorer.categories(_catalog_cache)}
  cat_dd.selected_index = 1

  window.add{
    type = "label",
    caption = "[color=150,150,150]Vert = deja relie a un effet Chroma (clique pour l'ouvrir dans Configuration). "
      .. "Le reste est juste pour reference -- dis quels events t'interessent pour qu'on les cable.[/color]",
  }

  local list_scroll = window.add{type = "scroll-pane", name = "chroma_explorer_list", direction = "vertical"}
  list_scroll.style.minimal_width = 520
  list_scroll.style.maximal_height = 420

  window.add{type = "label", name = "chroma_explorer_count_label", caption = ""}

  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_explorer_close_button", caption = "Fermer"}

  build_explorer_list(player)
end

-- --- Alertes personnalisees (haut-parleurs programmables) ---
-- Onglet dedie pour ajouter/supprimer des "watches" : {id, label, match_text}.
-- Une fois ajoutee, chaque watch apparait dans la liste principale
-- (build_list, cle "custom_<id>") pour choisir couleur/device/priorite avec
-- l'editeur d'alertes generique existant -- aucun code Python necessaire,
-- count_custom_alert_watches (control.lua) alimente alerts_by_type comme
-- n'importe quelle autre alerte.
local function build_watches_editor(player)
  local window = player.gui.screen.chroma_watches_window
  if not window then return end
  local list = window.chroma_watches_list
  list.clear()

  local draft = storage.chroma_watches_draft[player.index]
  for i, watch in ipairs(draft) do
    local row = list.add{type = "flow", name = "chroma_watch_row__" .. i, direction = "horizontal"}
    row.add{type = "label", caption = "Nom :"}
    row.add{type = "textfield", name = "chroma_watch_label__" .. i, text = watch.label or ""}
    row.add{type = "label", caption = "Texte a detecter (message du haut-parleur) :"}
    local match_field = row.add{type = "textfield", name = "chroma_watch_match__" .. i, text = watch.match_text or ""}
    match_field.style.minimal_width = 200
    row.add{type = "button", name = "chroma_watch_remove__" .. i, caption = "Supprimer"}
  end

  if #draft == 0 then
    list.add{type = "label", caption = "(aucune alerte personnalisee pour l'instant)"}
  end
end

function gui.toggle_watches_editor(player)
  local screen = player.gui.screen
  if screen.chroma_watches_window then
    screen.chroma_watches_window.destroy()
    return
  end

  storage.chroma_watches_draft = storage.chroma_watches_draft or {}
  storage.chroma_watches_draft[player.index] = deep_copy(player_mapping(player).custom_alert_watches or {})

  local window = screen.add{
    type = "frame", name = "chroma_watches_window", direction = "vertical",
    caption = "Chroma Bridge - Alertes personnalisees",
  }
  window.auto_center = true

  window.add{
    type = "label",
    caption = "[color=150,150,150]Detecte le message d'un haut-parleur programmable (case 'Alerte' cochee + texte "
      .. "libre, ex: 'Automall Frozen!!'). La correspondance ignore la casse et cherche le texte n'importe ou dans "
      .. "le message. Une fois appliquee, la watch apparait dans Configuration pour choisir sa couleur.[/color]",
  }

  local list_scroll = window.add{type = "scroll-pane", name = "chroma_watches_list", direction = "vertical"}
  list_scroll.style.minimal_width = 560
  list_scroll.style.maximal_height = 300

  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_watch_add_button", caption = "+ Ajouter une alerte"}
  bottom.add{type = "button", name = "chroma_watches_apply_button", caption = "Appliquer"}
  bottom.add{type = "button", name = "chroma_watches_close_button", caption = "Fermer"}

  build_watches_editor(player)
end

function gui.toggle(player)
  local screen = player.gui.screen
  if screen.chroma_bridge_window then
    screen.chroma_bridge_window.destroy()
    storage.chroma_draft[player.index] = nil
    return
  end

  local window = screen.add{type = "frame", name = "chroma_bridge_window", direction = "vertical", caption = "Chroma Bridge - Configuration"}
  window.auto_center = true

  local top = window.add{type = "flow", direction = "horizontal"}
  top.add{type = "label", caption = "Layout clavier :"}
  local layout_dd = top.add{type = "drop-down", name = "chroma_layout_dropdown", items = {"AZERTY (France)", "QWERTY (US)"}}
  layout_dd.selected_index = (current_layout_name(player) == "qwerty_us") and 2 or 1

  local body = window.add{type = "flow", name = "chroma_body", direction = "horizontal"}
  body.style.horizontal_spacing = 12

  local list_scroll = body.add{type = "scroll-pane", name = "chroma_list_scroll", direction = "vertical"}
  list_scroll.style.minimal_width = 280
  list_scroll.style.maximal_height = 480
  build_list(list_scroll, player)

  local detail = body.add{type = "flow", name = "chroma_detail_flow", direction = "vertical"}
  detail.style.minimal_width = 320
  detail.add{type = "label", caption = "Selectionne un evenement ou une alerte a gauche."}

  window.add{type = "line"}
  local bottom = window.add{type = "flow", direction = "horizontal"}
  bottom.add{type = "button", name = "chroma_close_button", caption = "Fermer"}
  bottom.add{type = "button", name = "chroma_open_explorer_button", caption = "Explorateur d'evenements"}
  bottom.add{type = "button", name = "chroma_open_research_button", caption = "Barre de recherche"}
  bottom.add{type = "button", name = "chroma_open_health_button", caption = "Barre de vie"}
  bottom.add{type = "button", name = "chroma_open_default_button", caption = "Couleur par defaut"}
  bottom.add{type = "button", name = "chroma_open_watches_button", caption = "Alertes personnalisees"}

  player.opened = window
end

function gui.on_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  local name = element.name

  if name == "chroma_close_button" then
    if player.gui.screen.chroma_bridge_window then
      player.gui.screen.chroma_bridge_window.destroy()
    end
    storage.chroma_draft[player.index] = nil
    return
  end

  local section, key = name:match("^chroma_select__(%a+)__(.+)$")
  if section and key then
    select_item(player, section, key)
    build_detail(player)
    return
  end

  local preset_index = name:match("^chroma_color_preset__(%d+)$")
  if preset_index then
    local draft = storage.chroma_draft[player.index]
    if draft then
      draft.cfg.color = deep_copy(COLOR_PRESETS[tonumber(preset_index)])
      build_detail(player)
    end
    return
  end

  if name == "chroma_apply_button" then
    local draft = storage.chroma_draft[player.index]
    if draft then
      local mapping = player_mapping(player)
      mapping[draft.section] = mapping[draft.section] or {}
      mapping[draft.section][draft.key] = deep_copy(draft.cfg)
      write_mapping_file(player)
      player.print("Chroma Bridge : '" .. draft.key .. "' mis a jour.")
    end
    return
  end

  if name == "chroma_open_explorer_button" then
    gui.toggle_explorer(player)
    return
  end

  if name == "chroma_open_research_button" then
    gui.toggle_research_bar_editor(player)
    return
  end

  if name == "chroma_rb_close_button" then
    if player.gui.screen.chroma_research_window then
      player.gui.screen.chroma_research_window.destroy()
    end
    return
  end

  if name == "chroma_rb_open_picker_button" then
    gui.toggle_keyboard_picker(player, "research_bar")
    return
  end

  if name == "chroma_rb_apply_button" then
    local draft = storage.chroma_research_draft[player.index]
    if draft then
      player_mapping(player).research_bar = deep_copy(draft)
      write_mapping_file(player)
      player.print("Chroma Bridge : barre de recherche mise a jour.")
    end
    return
  end

  local rb_bar_preset = name:match("^chroma_rb_bar_preset__(%d+)$")
  if rb_bar_preset then
    local draft = storage.chroma_research_draft[player.index]
    if draft then
      draft.color_bar = deep_copy(COLOR_PRESETS[tonumber(rb_bar_preset)])
      build_research_bar_editor(player)
    end
    return
  end

  local rb_empty_preset = name:match("^chroma_rb_empty_preset__(%d+)$")
  if rb_empty_preset then
    local draft = storage.chroma_research_draft[player.index]
    if draft then
      draft.color_empty = deep_copy(COLOR_PRESETS[tonumber(rb_empty_preset)])
      build_research_bar_editor(player)
    end
    return
  end

  if name == "chroma_open_health_button" then
    gui.toggle_health_bar_editor(player)
    return
  end

  if name == "chroma_hb_close_button" then
    if player.gui.screen.chroma_health_window then
      player.gui.screen.chroma_health_window.destroy()
    end
    return
  end

  if name == "chroma_hb_open_picker_button" then
    gui.toggle_keyboard_picker(player, "health_bar")
    return
  end

  if name == "chroma_hb_apply_button" then
    local draft = storage.chroma_health_draft[player.index]
    if draft then
      player_mapping(player).health_bar = deep_copy(draft)
      write_mapping_file(player)
      player.print("Chroma Bridge : barre de vie mise a jour.")
    end
    return
  end

  local hb_bar_preset = name:match("^chroma_hb_bar_preset__(%d+)$")
  if hb_bar_preset then
    local draft = storage.chroma_health_draft[player.index]
    if draft then
      draft.color_bar = deep_copy(COLOR_PRESETS[tonumber(hb_bar_preset)])
      build_health_bar_editor(player)
    end
    return
  end

  local hb_empty_preset = name:match("^chroma_hb_empty_preset__(%d+)$")
  if hb_empty_preset then
    local draft = storage.chroma_health_draft[player.index]
    if draft then
      draft.color_empty = deep_copy(COLOR_PRESETS[tonumber(hb_empty_preset)])
      build_health_bar_editor(player)
    end
    return
  end

  if name == "chroma_open_default_button" then
    gui.toggle_default_color_editor(player)
    return
  end

  if name == "chroma_kd_close_button" then
    if player.gui.screen.chroma_default_window then
      player.gui.screen.chroma_default_window.destroy()
    end
    return
  end

  if name == "chroma_kd_apply_button" then
    local draft = storage.chroma_default_draft[player.index]
    if draft then
      local mapping = player_mapping(player)
      mapping.keyboard_idle = deep_copy(draft)
      -- Meme couleur par defaut pour la souris/le tapis (mapping.ambient,
      -- cote Python) : on ne touche que color1/color2 ici, pas
      -- devices/thresholds qui restent geres dans mapping.json.
      mapping.ambient = mapping.ambient or {}
      mapping.ambient.color1 = deep_copy(draft.color1)
      mapping.ambient.color2 = deep_copy(draft.color2)
      write_mapping_file(player)
      player.print("Chroma Bridge : couleur par defaut mise a jour.")
    end
    return
  end

  local kd_c1_preset = name:match("^chroma_kd_c1_preset__(%d+)$")
  if kd_c1_preset then
    local draft = storage.chroma_default_draft[player.index]
    if draft then
      draft.color1 = deep_copy(COLOR_PRESETS[tonumber(kd_c1_preset)])
      build_default_color_editor(player)
    end
    return
  end

  local kd_c2_preset = name:match("^chroma_kd_c2_preset__(%d+)$")
  if kd_c2_preset then
    local draft = storage.chroma_default_draft[player.index]
    if draft then
      draft.color2 = deep_copy(COLOR_PRESETS[tonumber(kd_c2_preset)])
      build_default_color_editor(player)
    end
    return
  end

  if name == "chroma_open_watches_button" then
    gui.toggle_watches_editor(player)
    return
  end

  if name == "chroma_watches_close_button" then
    if player.gui.screen.chroma_watches_window then
      player.gui.screen.chroma_watches_window.destroy()
    end
    return
  end

  if name == "chroma_watch_add_button" then
    local draft = storage.chroma_watches_draft[player.index]
    if draft then
      local mapping = player_mapping(player)
      local id = mapping.next_watch_id or 1
      mapping.next_watch_id = id + 1
      table.insert(draft, {id = id, label = "", match_text = ""})
      build_watches_editor(player)
    end
    return
  end

  local remove_index = name:match("^chroma_watch_remove__(%d+)$")
  if remove_index then
    local draft = storage.chroma_watches_draft[player.index]
    if draft then
      table.remove(draft, tonumber(remove_index))
      build_watches_editor(player)
    end
    return
  end

  if name == "chroma_watches_apply_button" then
    local draft = storage.chroma_watches_draft[player.index]
    if draft then
      local mapping = player_mapping(player)
      local kept_ids = {}
      for _, watch in ipairs(draft) do
        kept_ids["custom_" .. watch.id] = true
      end
      -- Nettoie les entrees alerts orphelines des watches supprimees --
      -- sinon elles restent invisibles dans mapping.json indefiniment.
      for key in pairs(mapping.alerts) do
        if key:match("^custom_%d+$") and not kept_ids[key] then
          mapping.alerts[key] = nil
        end
      end
      mapping.custom_alert_watches = deep_copy(draft)
      write_mapping_file(player)
      player.print("Chroma Bridge : alertes personnalisees mises a jour.")
      if player.gui.screen.chroma_bridge_window then
        build_list(player.gui.screen.chroma_bridge_window.chroma_body.chroma_list_scroll, player)
      end
    end
    return
  end

  if name == "chroma_explorer_close_button" then
    if player.gui.screen.chroma_explorer_window then
      player.gui.screen.chroma_explorer_window.destroy()
    end
    return
  end

  local ekind, ekey = name:match("^chroma_explorer_goto__(%a+)__(.+)$")
  if ekind and ekey then
    local section = (ekind == "event") and "events" or "alerts"
    select_item(player, section, ekey)
    if not player.gui.screen.chroma_bridge_window then
      gui.toggle(player)
    end
    build_detail(player)
    player.print("Chroma Bridge : '" .. ekey .. "' ouvert dans l'onglet Configuration.")
    return
  end

  if name == "chroma_open_keyboard_picker_button" then
    gui.toggle_keyboard_picker(player, "event_scope")
    return
  end

  if name == "chroma_picker_cancel_button" then
    if player.gui.screen.chroma_keyboard_picker_window then
      player.gui.screen.chroma_keyboard_picker_window.destroy()
    end
    return
  end

  if name == "chroma_picker_clear_button" then
    storage.chroma_picker_selection[player.index] = {}
    build_keyboard_picker_grid(player)
    update_picker_summary(player)
    return
  end

  if name == "chroma_picker_confirm_button" then
    local selection = deep_copy(storage.chroma_picker_selection[player.index])
    local target = storage.chroma_picker_target[player.index]
    if target == "research_bar" then
      local rb_draft = storage.chroma_research_draft[player.index]
      if rb_draft then
        rb_draft.keys = selection
      end
      if player.gui.screen.chroma_keyboard_picker_window then
        player.gui.screen.chroma_keyboard_picker_window.destroy()
      end
      build_research_bar_editor(player)
    elseif target == "health_bar" then
      local hb_draft = storage.chroma_health_draft[player.index]
      if hb_draft then
        hb_draft.keys = selection
      end
      if player.gui.screen.chroma_keyboard_picker_window then
        player.gui.screen.chroma_keyboard_picker_window.destroy()
      end
      build_health_bar_editor(player)
    else
      local draft = storage.chroma_draft[player.index]
      if draft then
        draft.cfg.scope = selection
      end
      if player.gui.screen.chroma_keyboard_picker_window then
        player.gui.screen.chroma_keyboard_picker_window.destroy()
      end
      build_detail(player)
    end
    return
  end

  local prow, pcol = name:match("^chroma_picker_key__(%d+)__(%d+)$")
  if prow and pcol then
    local by_pos = inverse_layout(current_layout_name(player))
    local label = by_pos[prow .. ":" .. pcol]
    if label then
      local selection = storage.chroma_picker_selection[player.index]
      local idx = picker_index_of(selection, label)
      if idx then
        table.remove(selection, idx)
      else
        table.insert(selection, label)
      end
      build_keyboard_picker_grid(player)
      update_picker_summary(player)
    end
  end
end

function gui.on_checked_state_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)

  if element.name == "chroma_rb_enabled_checkbox" then
    local rb_draft = storage.chroma_research_draft[player.index]
    if rb_draft then rb_draft.enabled = element.state end
    return
  end

  if element.name == "chroma_hb_enabled_checkbox" then
    local hb_draft = storage.chroma_health_draft[player.index]
    if hb_draft then hb_draft.enabled = element.state end
    return
  end

  if element.name == "chroma_kd_ambient_checkbox" then
    local kd_draft = storage.chroma_default_draft[player.index]
    if kd_draft then kd_draft.ambient_reactive = element.state end
    return
  end

  local draft = storage.chroma_draft[player.index]
  if not draft then return end

  if element.name == "chroma_enabled_checkbox" then
    draft.cfg.enabled = element.state
  elseif element.name == "chroma_blink_checkbox" then
    draft.cfg.blink = element.state
    build_detail(player)
  elseif element.name == "chroma_style_spectrum_checkbox" then
    draft.cfg.style = element.state and "spectrum" or nil
    build_detail(player)
  end
end

function gui.on_selection_state_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)

  if element.name == "chroma_layout_dropdown" then
    player_mapping(player).layout = (element.selected_index == 2) and "qwerty_us" or "azerty_fr"
    write_mapping_file(player)
    return
  end

  if element.name == "chroma_explorer_category_dropdown" then
    local categories = event_explorer.categories(_catalog_cache)
    storage.chroma_explorer_state[player.index].category = categories[element.selected_index]
    build_explorer_list(player)
    return
  end

  local draft = storage.chroma_draft[player.index]
  if not draft then return end

  if element.name == "chroma_device_dropdown" then
    draft.cfg.device = DEVICES[element.selected_index].key
    build_detail(player)
  elseif element.name == "chroma_zone_dropdown" then
    local zone = ZONES[element.selected_index]
    if zone.key == "__keyboard_picker__" then
      if type(draft.cfg.scope) ~= "table" then
        draft.cfg.scope = {}
      end
    elseif zone.key ~= "__custom__" then
      draft.cfg.scope = zone.key
    elseif is_known_zone(draft.cfg.scope) or type(draft.cfg.scope) == "table" then
      draft.cfg.scope = ""
    end
    build_detail(player)
  end
end

function gui.on_text_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)

  if element.name == "chroma_explorer_search" then
    storage.chroma_explorer_state[player.index].search = element.text
    build_explorer_list(player)
    return
  end

  local watch_label_index = element.name:match("^chroma_watch_label__(%d+)$")
  if watch_label_index then
    local draft = storage.chroma_watches_draft[player.index]
    if draft and draft[tonumber(watch_label_index)] then
      draft[tonumber(watch_label_index)].label = element.text
    end
    return
  end

  local watch_match_index = element.name:match("^chroma_watch_match__(%d+)$")
  if watch_match_index then
    local draft = storage.chroma_watches_draft[player.index]
    if draft and draft[tonumber(watch_match_index)] then
      draft[tonumber(watch_match_index)].match_text = element.text
    end
    return
  end

  if element.name ~= "chroma_custom_key_field" then return end
  local draft = storage.chroma_draft[player.index]
  if not draft then return end
  draft.cfg.scope = element.text ~= "" and element.text:upper() or "all"
end

function gui.on_value_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  local name = element.name
  local value = element.slider_value

  if name == "chroma_rb_bar_slider_r" or name == "chroma_rb_bar_slider_g" or name == "chroma_rb_bar_slider_b" then
    local rb_draft = storage.chroma_research_draft[player.index]
    if rb_draft then
      rb_draft.color_bar = rb_draft.color_bar or {0, 255, 60}
      if name == "chroma_rb_bar_slider_r" then rb_draft.color_bar[1] = value end
      if name == "chroma_rb_bar_slider_g" then rb_draft.color_bar[2] = value end
      if name == "chroma_rb_bar_slider_b" then rb_draft.color_bar[3] = value end
      build_research_bar_editor(player)
    end
    return
  end

  if name == "chroma_rb_empty_slider_r" or name == "chroma_rb_empty_slider_g" or name == "chroma_rb_empty_slider_b" then
    local rb_draft = storage.chroma_research_draft[player.index]
    if rb_draft then
      rb_draft.color_empty = rb_draft.color_empty or {20, 20, 20}
      if name == "chroma_rb_empty_slider_r" then rb_draft.color_empty[1] = value end
      if name == "chroma_rb_empty_slider_g" then rb_draft.color_empty[2] = value end
      if name == "chroma_rb_empty_slider_b" then rb_draft.color_empty[3] = value end
      build_research_bar_editor(player)
    end
    return
  end

  if name == "chroma_hb_bar_slider_r" or name == "chroma_hb_bar_slider_g" or name == "chroma_hb_bar_slider_b" then
    local hb_draft = storage.chroma_health_draft[player.index]
    if hb_draft then
      hb_draft.color_bar = hb_draft.color_bar or {0, 255, 0}
      if name == "chroma_hb_bar_slider_r" then hb_draft.color_bar[1] = value end
      if name == "chroma_hb_bar_slider_g" then hb_draft.color_bar[2] = value end
      if name == "chroma_hb_bar_slider_b" then hb_draft.color_bar[3] = value end
      build_health_bar_editor(player)
    end
    return
  end

  if name == "chroma_hb_empty_slider_r" or name == "chroma_hb_empty_slider_g" or name == "chroma_hb_empty_slider_b" then
    local hb_draft = storage.chroma_health_draft[player.index]
    if hb_draft then
      hb_draft.color_empty = hb_draft.color_empty or {40, 0, 0}
      if name == "chroma_hb_empty_slider_r" then hb_draft.color_empty[1] = value end
      if name == "chroma_hb_empty_slider_g" then hb_draft.color_empty[2] = value end
      if name == "chroma_hb_empty_slider_b" then hb_draft.color_empty[3] = value end
      build_health_bar_editor(player)
    end
    return
  end

  if name == "chroma_kd_c1_slider_r" or name == "chroma_kd_c1_slider_g" or name == "chroma_kd_c1_slider_b" then
    local kd_draft = storage.chroma_default_draft[player.index]
    if kd_draft then
      kd_draft.color1 = kd_draft.color1 or {230, 100, 20}
      if name == "chroma_kd_c1_slider_r" then kd_draft.color1[1] = value end
      if name == "chroma_kd_c1_slider_g" then kd_draft.color1[2] = value end
      if name == "chroma_kd_c1_slider_b" then kd_draft.color1[3] = value end
      build_default_color_editor(player)
    end
    return
  end

  if name == "chroma_kd_c2_slider_r" or name == "chroma_kd_c2_slider_g" or name == "chroma_kd_c2_slider_b" then
    local kd_draft = storage.chroma_default_draft[player.index]
    if kd_draft then
      kd_draft.color2 = kd_draft.color2 or {20, 10, 0}
      if name == "chroma_kd_c2_slider_r" then kd_draft.color2[1] = value end
      if name == "chroma_kd_c2_slider_g" then kd_draft.color2[2] = value end
      if name == "chroma_kd_c2_slider_b" then kd_draft.color2[3] = value end
      build_default_color_editor(player)
    end
    return
  end

  local draft = storage.chroma_draft[player.index]
  if not draft then return end

  if name == "chroma_slider_r" or name == "chroma_slider_g" or name == "chroma_slider_b" then
    draft.cfg.color = draft.cfg.color or {255, 255, 255}
    if name == "chroma_slider_r" then draft.cfg.color[1] = value end
    if name == "chroma_slider_g" then draft.cfg.color[2] = value end
    if name == "chroma_slider_b" then draft.cfg.color[3] = value end
    build_detail(player)
  elseif name == "chroma_blink_slider" then
    draft.cfg.blink_interval = value / 10
    build_detail(player)
  elseif name == "chroma_hold_slider" then
    draft.cfg.hold = value / 10
    build_detail(player)
  elseif name == "chroma_priority_slider" then
    draft.cfg.priority = value
    build_detail(player)
  end
end

function gui.on_closed(event)
  local element = event.element
  if element and element.valid and element.name == "chroma_bridge_window" then
    element.destroy()
    storage.chroma_draft[event.player_index] = nil
  end
end

return gui
