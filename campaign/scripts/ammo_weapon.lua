-- 
-- Please see the LICENSE.md file included with this distribution for 
-- attribution and copyright information.
--

function onInit()
	registerMenuItem(Interface.getString("menu_deleteweapon"), "delete", 4);
	registerMenuItem(Interface.getString("list_menu_deleteconfirm"), "delete", 4, 3);
	
	local sNode = getDatabaseNode().getPath();
	DB.addHandler(sNode, "onChildUpdate", onDataChanged);
	onDataChanged();
end
function onClose()
	local sNode = getDatabaseNode().getPath();
	DB.removeHandler(sNode, "onChildUpdate", onDataChanged);
end
function hasLoadAction(nodeWeapon)
	local bHasLoadAction
	local bRanged = (type.getValue() == 1);
	local sWeaponName = string.lower(DB.getValue(nodeWeapon, 'name', 'ranged weapon'));
	for _,v in pairs(AmmunitionManager.tLoadWeapons) do
		if string.find(sWeaponName, v) then bHasLoadAction = true; break; end
	end

	return (bRanged and bHasLoadAction)
end
function automateAmmo(nodeWeapon)
	local bNotLoaded = (DB.getValue(nodeWeapon, 'isloaded') == 0);
	DB.setValue(nodeWeapon, 'isloaded', 'number', 0);
	if hasLoadAction(nodeWeapon) and bNotLoaded then
		local rActor = ActorManager.resolveActor(nodeWeapon.getChild('...'));
		local sWeaponName = string.lower(DB.getValue(nodeWeapon, 'name', 'ranged weapon'));

		ChatManager.Message(string.format(Interface.getString('char_actions_notloaded'), sWeaponName), true, rActor);
		return true;
	end
end
function onDataChanged()
	onLinkChanged();
	onDamageChanged();
	
	local nodeWeapon = getDatabaseNode();
	local rActor = ActorManager.resolveActor(nodeWeapon.getChild('...'));

	local bRanged = (type.getValue() == 1);
	label_range.setVisible(bRanged);
	rangeincrement.setVisible(bRanged);
	isloaded.setVisible(hasLoadAction(nodeWeapon));

	if not AmmunitionManager.isAmmoPicker(nodeWeapon, rActor) then
		label_ammo.setVisible(bRanged);
		maxammo.setVisible(bRanged);
		ammocounter.setVisible(bRanged);
	else
		label_ammo.setVisible(false);
		maxammo.setVisible(false);
		ammocounter.setVisible(false);
	end
end