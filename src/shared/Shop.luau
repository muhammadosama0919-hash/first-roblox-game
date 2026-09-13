--!strict
--[[
	What the shop sells.

	This lives in ReplicatedStorage so the client can draw the shop menu from
	the same list the server charges against. The client using this list is a
	convenience, not a source of authority — the server re-reads every price
	from here when a purchase comes in, so a tampered client cannot invent an
	item or change what something costs.
]]

export type Item = {
	id: string,
	name: string,
	description: string,
	price: number,
	-- Effects. All optional; an item applies whichever ones it sets.
	walkSpeedBonus: number?,
	jumpPowerBonus: number?,
	coinMultiplier: number?,
}

-- Order here is the order they appear in the menu.
local ITEMS: { Item } = {
	{
		id = "swiftBoots",
		name = "Swift Boots",
		description = "Move noticeably faster.",
		price = 25,
		walkSpeedBonus = 8,
	},
	{
		id = "springLegs",
		name = "Spring Legs",
		description = "Jump half again as high.",
		price = 50,
		jumpPowerBonus = 25,
	},
	{
		id = "luckyCharm",
		name = "Lucky Charm",
		description = "Every coin is worth double.",
		price = 100,
		coinMultiplier = 2,
	},
}

local Shop = {}

Shop.items = ITEMS

function Shop.getItem(id: string): Item?
	for _, item in Shop.items do
		if item.id == id then
			return item
		end
	end

	return nil
end

return Shop
