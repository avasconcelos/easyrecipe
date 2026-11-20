local _, ns = ...

local L = {
    HEADER = "Recipes using this item",
    MORE = "+%d more (hold Shift while hovering)",
    HINT = "open each of your profession windows once so your recipes can be recorded.",
    SCANNED = "%d known recipes recorded.",
    ENABLED = "tooltip lines enabled.",
    DISABLED = "tooltip lines disabled.",
    MAX_SET = "showing up to %d recipes per tooltip.",
    MAX_USAGE = "usage: /easyrecipe max <number>",
    RESET = "recipe data cleared. Open your profession windows again to rebuild it.",
    NO_TOOLTIP_API = "this client has no tooltip data API, so tooltips are left untouched.",
    STATUS_LEVELS = "Crafted item recorded for %d recipes, its required level for %d.",
    EXTRA_ERROR = "something could not be set up: %s",
    NO_OPTIONS = "the options panel is not available. Use the /easyrecipe commands instead.",
    OPTIONS_COMBAT = "the options can't be opened in combat. Try again after the fight.",
    OPT_GENERAL = "General",
    OPT_ENABLED = "Show recipes in tooltips",
    OPT_ENABLED_TIP = "List your recipes in the tooltip of the reagents they use.",
    OPT_MINIMAP = "Minimap button",
    OPT_MINIMAP_TIP = "Show the EasyRecipe button around the minimap.",
    OPT_MAX = "Recipes per tooltip",
    OPT_MAX_TIP = "How many recipes a tooltip lists. Hold Shift while hovering to see up to %d.",
    OPT_DIFFICULTY = "Difficulty",
    OPT_OPTIMAL = "Orange",
    OPT_MEDIUM = "Yellow",
    OPT_EASY = "Green",
    OPT_TRIVIAL = "Gray",
    OPT_DIFFICULTY_TIP = "List the recipes that have this color in your profession window.",
    OPT_LEVEL = "Level of the crafted item",
    OPT_MIN_LEVEL = "Lowest level",
    OPT_MAX_LEVEL = "Highest level",
    OPT_LEVEL_TIP = "A recipe is listed when the level required to use the item it makes is within this range. Recipes for items anyone can use, such as bars and bolts of cloth, and for enchantments are always listed.",
    OPT_LOOT = "Loot",
    OPT_LOOT_UNIT = "What a creature drops",
    OPT_LOOT_UNIT_TIP = "When you hover a creature, list what you have already looted from that kind of creature, and how often.",
    OPT_LOOT_REAGENTS = "Only crafting reagents",
    OPT_LOOT_REAGENTS_TIP = "On a creature, list only the items professions use, such as meat, leather and cloth.",
    OPT_LOOT_ITEM = "Where an item drops",
    OPT_LOOT_ITEM_TIP = "In an item's tooltip, list the creatures and fishing spots you have looted it from.",
    DROPS_UNIT = "Already dropped (%d looted)",
    DROPS_ITEM = "Drops from",
    FISHING = "Fishing: %s",
    UNKNOWN_CREATURE = "Creature #%d",
    STATUS_LOOT = "Loot recorded from %d kinds of creatures and %d fishing spots.",
    LOOT_RESET = "loot records cleared.",
    OPT_PROFESSIONS = "Professions of this character",
    OPT_PROFESSION_TIP = "List the recipes of this profession.",
    MINIMAP_LEFT = "Left-click: recipe book",
    MINIMAP_RIGHT = "Right-click: options",
    OPENED_FROM = "%s (from %s)",
    BOOK_TITLE = "EasyRecipe - Recipe book",
    BOOK_CRAFTABLE = "Can craft",
    BOOK_ALMOST = "Almost there",
    BOOK_ALL = "All",
    BOOK_BEASTS = "Beasts",
    BOOK_OTHER = "Other",
    BOOK_LOOTED = "%d looted",
    BOOK_EMPTY_CRAFTABLE = "Nothing to craft with what is in your bags and bank.",
    BOOK_EMPTY_ALMOST = "No recipe with only some of its reagents in your bags and bank.",
    BOOK_EMPTY_ALL = "No recipes yet: open each of your profession windows once.",
    BOOK_EMPTY_BEASTS = "No creatures yet: they are listed as you loot them.",
    INTRO_TITLE = "Welcome to EasyRecipe",
    INTRO_TEXT = "EasyRecipe learns along with your character: it starts empty and fills in as you play.\n\n"
        .. "1. Open each of your profession windows once, so your recipes can be recorded.\n\n"
        .. "2. Hover a reagent in your bags or bank: the tooltip lists your recipes that use it, by profession.\n\n"
        .. "3. Loot creatures and fish as usual: hovering a creature then shows what it has dropped for you, "
        .. "and an item shows where it drops.\n\n"
        .. "4. Click the EasyRecipe button on the minimap for the recipe book: what you can craft with your bags "
        .. "and bank, what you almost can, and every creature you have looted. Right-click it, or type "
        .. "/easyrecipe config, to choose what is listed.",
    INTRO_OPTIONS = "Open the options",
    INTRO_OK = "Got it",
    HELP = {
        "/easyrecipe book - open the recipe book",
        "/easyrecipe config - open the options",
        "/easyrecipe on | off - enable or disable the tooltip lines",
        "/easyrecipe max <number> - recipes shown per tooltip",
        "/easyrecipe reset - clear this character's recorded recipes",
        "/easyrecipe resetloot - clear the loot records of every character",
    },
}

if GetLocale() == "ptBR" then
    L.HEADER = "Receitas que usam este item"
    L.MORE = "+%d receitas (segure Shift ao passar o mouse)"
    L.HINT = "abra a janela de cada profissão uma vez para que suas receitas sejam registradas."
    L.SCANNED = "%d receitas conhecidas registradas."
    L.ENABLED = "linhas no tooltip ativadas."
    L.DISABLED = "linhas no tooltip desativadas."
    L.MAX_SET = "mostrando até %d receitas por tooltip."
    L.MAX_USAGE = "uso: /easyrecipe max <número>"
    L.RESET = "dados de receitas apagados. Abra suas profissões de novo para refazer o registro."
    L.NO_TOOLTIP_API = "este cliente não tem a API de dados de tooltip, então os tooltips não são alterados."
    L.STATUS_LEVELS = "Item fabricado registrado em %d receitas, o nível exigido dele em %d."
    L.EXTRA_ERROR = "algo não pôde ser preparado: %s"
    L.NO_OPTIONS = "o painel de opções não está disponível. Use os comandos /easyrecipe."
    L.OPTIONS_COMBAT = "as opções não podem ser abertas em combate. Tente de novo depois da luta."
    L.OPT_GENERAL = "Geral"
    L.OPT_ENABLED = "Mostrar receitas nos tooltips"
    L.OPT_ENABLED_TIP = "Lista suas receitas no tooltip dos reagentes que elas usam."
    L.OPT_MINIMAP = "Botão no minimapa"
    L.OPT_MINIMAP_TIP = "Mostra o botão do EasyRecipe em volta do minimapa."
    L.OPT_MAX = "Receitas por tooltip"
    L.OPT_MAX_TIP = "Quantas receitas um tooltip lista. Segure Shift ao passar o mouse para ver até %d."
    L.OPT_DIFFICULTY = "Dificuldade"
    L.OPT_OPTIMAL = "Laranja"
    L.OPT_MEDIUM = "Amarela"
    L.OPT_EASY = "Verde"
    L.OPT_TRIVIAL = "Cinza"
    L.OPT_DIFFICULTY_TIP = "Lista as receitas que têm esta cor na janela da sua profissão."
    L.OPT_LEVEL = "Nível do item fabricado"
    L.OPT_MIN_LEVEL = "Nível mínimo"
    L.OPT_MAX_LEVEL = "Nível máximo"
    L.OPT_LEVEL_TIP = "Uma receita é listada quando o nível exigido para usar o item que ela faz está dentro desta faixa. Receitas de itens que qualquer um pode usar, como barras e peças de tecido, e de encantamentos são sempre listadas."
    L.OPT_LOOT = "Saque"
    L.OPT_LOOT_UNIT = "O que uma criatura deixa cair"
    L.OPT_LOOT_UNIT_TIP = "Ao passar o mouse numa criatura, lista o que você já saqueou desse tipo de criatura e com que frequência."
    L.OPT_LOOT_REAGENTS = "Só reagentes de profissão"
    L.OPT_LOOT_REAGENTS_TIP = "Na criatura, lista só os itens que as profissões usam, como carne, couro e tecido."
    L.OPT_LOOT_ITEM = "Onde um item cai"
    L.OPT_LOOT_ITEM_TIP = "No tooltip de um item, lista as criaturas e os lugares de pesca de onde você já o saqueou."
    L.DROPS_UNIT = "Já deixou cair (%d saqueados)"
    L.DROPS_ITEM = "Cai de"
    L.FISHING = "Pesca: %s"
    L.UNKNOWN_CREATURE = "Criatura nº %d"
    L.STATUS_LOOT = "Saque registrado de %d tipos de criatura e %d lugares de pesca."
    L.LOOT_RESET = "registros de saque apagados."
    L.OPT_PROFESSIONS = "Profissões deste personagem"
    L.OPT_PROFESSION_TIP = "Lista as receitas desta profissão."
    L.MINIMAP_LEFT = "Clique esquerdo: livro de receitas"
    L.MINIMAP_RIGHT = "Clique direito: opções"
    L.OPENED_FROM = "%s (de %s)"
    L.BOOK_TITLE = "EasyRecipe - Livro de receitas"
    L.BOOK_CRAFTABLE = "Dá para fazer"
    L.BOOK_ALMOST = "Falta pouco"
    L.BOOK_ALL = "Todas"
    L.BOOK_BEASTS = "Feras"
    L.BOOK_OTHER = "Outras"
    L.BOOK_LOOTED = "%d saqueados"
    L.BOOK_EMPTY_CRAFTABLE = "Nada para fazer com o que está na bolsa e no banco."
    L.BOOK_EMPTY_ALMOST = "Nenhuma receita com só parte dos reagentes na bolsa e no banco."
    L.BOOK_EMPTY_ALL = "Nenhuma receita ainda: abra a janela de cada profissão uma vez."
    L.BOOK_EMPTY_BEASTS = "Nenhuma criatura ainda: elas aparecem conforme você saqueia."
    L.INTRO_TITLE = "Bem-vindo ao EasyRecipe"
    L.INTRO_TEXT = "O EasyRecipe aprende junto com o seu personagem: começa vazio e vai se completando enquanto você joga.\n\n"
        .. "1. Abra a janela de cada profissão uma vez, para que suas receitas sejam registradas.\n\n"
        .. "2. Passe o mouse sobre um reagente na bolsa ou no banco: o tooltip lista as suas receitas que o usam, por profissão.\n\n"
        .. "3. Saqueie criaturas e pesque normalmente: depois, passar o mouse numa criatura mostra o que ela já deixou cair "
        .. "para você, e um item mostra de onde ele cai.\n\n"
        .. "4. Clique no botão do EasyRecipe no minimapa para o livro de receitas: o que dá para fazer com a bolsa "
        .. "e o banco, o que falta pouco e todas as criaturas que você já saqueou. Clique direito nele, ou "
        .. "digite /easyrecipe config, para escolher o que é listado."
    L.INTRO_OPTIONS = "Abrir as opções"
    L.INTRO_OK = "Entendi"
    L.HELP = {
        "/easyrecipe book - abre o livro de receitas",
        "/easyrecipe config - abre as opções",
        "/easyrecipe on | off - ativa ou desativa as linhas no tooltip",
        "/easyrecipe max <número> - receitas mostradas por tooltip",
        "/easyrecipe reset - apaga as receitas registradas deste personagem",
        "/easyrecipe resetloot - apaga os registros de saque de todos os personagens",
    }
end

ns.L = L
