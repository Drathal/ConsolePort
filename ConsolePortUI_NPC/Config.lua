local _, L = ...

function L.GetDefaultConfig()
	local t = {}
	for k, v in pairs(L.defaults) do
		t[k] = v
	end
	return t
end

function L.Get(val)
	return ( L.cfg and L.cfg[val] or L.defaults[val] )
end

function L.GetFromSV(tbl)
	local id = tbl[#tbl]
	return ( L.cfg and L.cfg[id])
end

function L.GetFromDefaultOrSV(tbl)
	local id = tbl[#tbl]
	return ( L.cfg and L.cfg[id]) or L.defaults[id]
end


----------------------------------
-- Default config
----------------------------------

L.defaults = {
----------------------------------
	scale = 1,

	titlescale = 1,
	titleoffset = -500,

	boxscale = 1,
	boxoffsetX = 0,
	boxoffsetY = 150,
	boxpoint = 'Bottom',

	disableprogression = false,
	delaydivisor = 15,
}---------------------------------