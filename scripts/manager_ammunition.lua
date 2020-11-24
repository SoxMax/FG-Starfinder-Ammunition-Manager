-- 
-- Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--

local onAttack_old = nil

-- Function Overrides
function onInit()
	-- back-up original copies
	onAttack_old = ActionAttack.onAttack;

	-- replace functions with new ones
	ActionAttack.onAttack = onAttack_new;
	
	-- remove original result handlers
	ActionsManager.unregisterResultHandler("attack");

	-- register new result handlers
	ActionsManager.registerResultHandler("attack", onAttack_new);
end

function onClose()
	-- restore original functions
	ActionAttack.onAttack = onAttack_old;

	-- remove result handlers
	ActionsManager.unregisterResultHandler("attack");

	-- re-register original result handlers
	ActionsManager.registerResultHandler("attack", ActionAttack.onAttack);
end

function onAttack_new(rSource, rTarget, rRoll)
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);

	local bIsSourcePC = (rSource and rSource.sType == "pc");
	local bAllowCC = OptionsManager.isOption("HRCC", "on") or (not bIsSourcePC and OptionsManager.isOption("HRCC", "npc"));
	
	if rRoll.sDesc:match("%[CMB") then
		rRoll.sType = "grapple";
	end
	
	local rAction = {};
	rAction.nTotal = ActionsManager.total(rRoll);
	rAction.aMessages = {};
	
	-- If we have a target, then calculate the defense we need to exceed
	local nDefenseVal, nAtkEffectsBonus, nDefEffectsBonus, nMissChance;
	if rRoll.sType == "critconfirm" then
		local sDefenseVal = string.match(rRoll.sDesc, " %[AC ([%-%+]?%d+)%]");
		if sDefenseVal then
			nDefenseVal = tonumber(sDefenseVal);
			-- Debug.console(nDefenseVal);
		end
		nMissChance = tonumber(string.match(rRoll.sDesc, "%[MISS CHANCE (%d+)%%%]")) or 0;
		rMessage.text = string.gsub(rMessage.text, " %[AC ([%-%+]?%d+)%]", "");
		rMessage.text = string.gsub(rMessage.text, " %[MISS CHANCE %d+%%%]", "");
		
		local sAtkEffectsMatch = " %[" .. Interface.getString("effects_tag") .. " ([+-]?%d+)%]";
		local sAtkEffectsBonus = string.match(rRoll.sDesc, sAtkEffectsMatch);
		if sAtkEffectsBonus then
			nAtkEffectsBonus = (tonumber(sAtkEffectsBonus) or 0);
			if nAtkEffectsBonus ~= 0 then 
				rAction.nTotal = rAction.nTotal + (tonumber(sAtkEffectsBonus) or 0);
				local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]";
				table.insert(rAction.aMessages, string.format(sFormat, nAtkEffectsBonus));
			end
			local sAtkEffectsClear = " %[" .. Interface.getString("effects_tag") .. " [+-]?%d+%]";
			rMessage.text = string.gsub(rMessage.text, sAtkEffectsClear, "");
		end
	else
		nDefenseVal, nAtkEffectsBonus, nDefEffectsBonus, nMissChance, nAdditionalDefenseForCC = ActorManager2.getDefenseValue(rSource, rTarget, rRoll);
		-- KEL CONC on Attacker
		-- DETERMINE ATTACK TYPE AND DEFENSE
		local AttackType = "M";
		if rRoll.sType == "attack" then
			AttackType = string.match(rRoll.sDesc, "%[ATTACK.*%((%w+)%)%]");
		end
		local Opportunity = string.match(rRoll.sDesc, "%[OPPORTUNITY%]");
		-- BUILD ATTACK FILTER 
		local AttackFilter = {};
		if AttackType == "M" then
			table.insert(AttackFilter, "melee");
		elseif AttackType == "R" then
			table.insert(AttackFilter, "ranged");
		end
		if Opportunity then
			table.insert(AttackFilter, "opportunity");
		end
		local aVConcealEffect, aVConcealCount = EffectManager35E.getEffectsBonusByType(rSource, "TVCONC", true, AttackFilter, rTarget, false, rRoll.tags);
		
		if aVConcealCount > 0 then
			rMessage.text = rMessage.text .. " [VCONC]";
			for _,v in  pairs(aVConcealEffect) do
				nMissChance = math.max(v.mod,nMissChance);
			end
		end
		-- END
		if nAtkEffectsBonus ~= 0 then
			rAction.nTotal = rAction.nTotal + nAtkEffectsBonus;
			local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]";
			table.insert(rAction.aMessages, string.format(sFormat, nAtkEffectsBonus));
		end
		if nDefEffectsBonus ~= 0 then
			nDefenseVal = nDefenseVal + nDefEffectsBonus;
			local sFormat = "[" .. Interface.getString("effects_def_tag") .. " %+d]";
			table.insert(rAction.aMessages, string.format(sFormat, nDefEffectsBonus));
		end
	end

	-- Get the crit threshold
	rAction.nCrit = 20;	
	local sAltCritRange = string.match(rRoll.sDesc, "%[CRIT (%d+)%]");
	if sAltCritRange then
		rAction.nCrit = tonumber(sAltCritRange) or 20;
		if (rAction.nCrit <= 1) or (rAction.nCrit > 20) then
			rAction.nCrit = 20;
		end
	end
	
	-- Check for Always a Chance (Ex) special ability (bmos)
	local bNoFumble = false
	if MythicAbilties and rSource then
		bNoFumble = hasSpecialAbility(rSource, 'Always a Chance')
	end
	-- end bmos addition
	
	rAction.nFirstDie = 0;
	if #(rRoll.aDice) > 0 then
		rAction.nFirstDie = rRoll.aDice[1].result or 0;
	end
	rAction.bCritThreat = false;
	if rAction.nFirstDie >= 20 then
		rAction.bSpecial = true;
		if rRoll.sType == "critconfirm" then
			rAction.sResult = "crit";
			table.insert(rAction.aMessages, "[CRITICAL HIT]");
		elseif rRoll.sType == "attack" then
			if bAllowCC then
				rAction.sResult = "hit";
				rAction.bCritThreat = true;
				table.insert(rAction.aMessages, "[AUTOMATIC HIT]");
			else
				rAction.sResult = "crit";
				table.insert(rAction.aMessages, "[CRITICAL HIT]");
			end
		else
			rAction.sResult = "hit";
			table.insert(rAction.aMessages, "[AUTOMATIC HIT]");
		end
	elseif not bNoFumble and rAction.nFirstDie == 1 then -- bmos added "not bNoFumble and"
		if rRoll.sType == "critconfirm" then
			table.insert(rAction.aMessages, "[CRIT NOT CONFIRMED]");
			rAction.sResult = "miss";
		else
			table.insert(rAction.aMessages, "[AUTOMATIC MISS]");
			rAction.sResult = "fumble";
		end
	elseif nDefenseVal then
		if rAction.nTotal >= nDefenseVal then
			if rRoll.sType == "critconfirm" then
				rAction.sResult = "crit";
				table.insert(rAction.aMessages, "[CRITICAL HIT]");
			elseif rRoll.sType == "attack" and rAction.nFirstDie >= rAction.nCrit then
				if bAllowCC then
					rAction.sResult = "hit";
					rAction.bCritThreat = true;
					table.insert(rAction.aMessages, "[CRITICAL THREAT]");
				else
					rAction.sResult = "crit";
					table.insert(rAction.aMessages, "[CRITICAL HIT]");
				end
			else
				rAction.sResult = "hit";
				table.insert(rAction.aMessages, "[HIT]");
			end
		else
			rAction.sResult = "miss";
			if rRoll.sType == "critconfirm" then
				table.insert(rAction.aMessages, "[CRIT NOT CONFIRMED]");
			else
				table.insert(rAction.aMessages, "[MISS]");
			end
		end
	elseif rRoll.sType == "critconfirm" then
		rAction.sResult = "crit";
		table.insert(rAction.aMessages, "[CHECK FOR CRITICAL]");
	elseif rRoll.sType == "attack" and rAction.nFirstDie >= rAction.nCrit then
		if bAllowCC then
			rAction.sResult = "hit";
			rAction.bCritThreat = true;
		else
			rAction.sResult = "crit";
		end
		table.insert(rAction.aMessages, "[CHECK FOR CRITICAL]");
	end
	
	if ((rRoll.sType == "critconfirm") or not rAction.bCritThreat) and (nMissChance > 0) then
		table.insert(rAction.aMessages, "[MISS CHANCE " .. nMissChance .. "%]");
	end

	Comm.deliverChatMessage(rMessage);

	if rAction.sResult == "crit" then
		ActionAttack.setCritState(rSource, rTarget);
	end
	
	local bRollMissChance = false;
	if rRoll.sType == "critconfirm" then
		bRollMissChance = true;
	else
		if rAction.bCritThreat then
			local rCritConfirmRoll = { sType = "critconfirm", aDice = {"d20"}, bTower = rRoll.bTower, bSecret = rRoll.bSecret };
			
			local nCCMod = EffectManager35E.getEffectsBonus(rSource, {"CC"}, true, nil, rTarget, false, rRoll.tags);
			if nCCMod ~= 0 then
				rCritConfirmRoll.sDesc = string.format("%s [CONFIRM %+d]", rRoll.sDesc, nCCMod);
			else
				rCritConfirmRoll.sDesc = rRoll.sDesc .. " [CONFIRM]";
			end
			if nMissChance > 0 then
				rCritConfirmRoll.sDesc = rCritConfirmRoll.sDesc .. " [MISS CHANCE " .. nMissChance .. "%]";
			end
			rCritConfirmRoll.nMod = rRoll.nMod + nCCMod;
			-- KEL ACCC stuff
			local nNewDefenseVal = 0;
			if nAdditionalDefenseForCC ~= 0 and nDefenseVal then
				nNewDefenseVal = nAdditionalDefenseForCC;
				rCritConfirmRoll.sDesc = rCritConfirmRoll.sDesc .. " [CC DEF EFFECTS " .. nAdditionalDefenseForCC .. "]";
			end
			-- END
			if nDefenseVal then
				--KEL
				nNewDefenseVal = nNewDefenseVal + nDefenseVal;
				rCritConfirmRoll.sDesc = rCritConfirmRoll.sDesc .. " [AC " .. nNewDefenseVal .. "]";
				--END
			end
			
			if nAtkEffectsBonus and nAtkEffectsBonus ~= 0 then
				local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]";
				rCritConfirmRoll.sDesc = rCritConfirmRoll.sDesc .. " " .. string.format(sFormat, nAtkEffectsBonus);
			end
			
			ActionsManager.roll(rSource, { rTarget }, rCritConfirmRoll, true);
		elseif (rAction.sResult ~= "miss") and (rAction.sResult ~= "fumble") then
			bRollMissChance = true;
		-- KEL compatibility test with mirror image handler
		elseif MirrorImageHandler and (rAction.sResult == "miss") and (nDefenseVal - rAction.nTotal <= 5) then
			bRollMissChance = true;
			nMissChance = 0;
		end
	end
	-- KEL Adding informations about Full attack to avoid loosing target on misschance, similar for action type
	local FullAttack = "";
	local ActionStuffForOverlay = "";
	if string.match(rRoll.sDesc, "%[FULL%]") then
		FulLAttack = "true";
	else
		FullAttack = "false";
	end
	if string.match(rRoll.sDesc, "%[ACTION%]") then
		ActionStuffForOverlay = "true";
	else
		ActionStuffForOverlay = "false";
	end
	-- END
	if bRollMissChance and (nMissChance > 0) then
		local aMissChanceDice = { "d100" };
		if not UtilityManager.isClientFGU() then
			table.insert(aMissChanceDice, "d10");
		end
		local sMissChanceText;
		sMissChanceText = string.gsub(rMessage.text, " %[CRIT %d+%]", "");
		sMissChanceText = string.gsub(sMissChanceText, " %[CONFIRM%]", "");
		local rMissChanceRoll = { sType = "misschance", sDesc = sMissChanceText .. " [MISS CHANCE " .. nMissChance .. "%]", aDice = aMissChanceDice, nMod = 0, fullattack = FullAttack, actionStuffForOverlay = ActionStuffForOverlay };
		ActionsManager.roll(rSource, rTarget, rMissChanceRoll);
		-- KEL compatibility test with mirror image handler
	elseif MirrorImageHandler and bRollMissChance then
		local nMirrorImageCount = MirrorImageHandler.getMirrorImageCount(rTarget);
		if nMirrorImageCount > 0 then
			if rAction.sResult == "hit" or rAction.sResult == "crit" or rRoll.sType == "critconfirm" then
				local rMirrorImageRoll = MirrorImageHandler.getMirrorImageRoll(nMirrorImageCount, rRoll.sDesc);
				ActionsManager.roll(rSource, rTarget, rMirrorImageRoll);
			elseif rRoll.sType ~= "critconfirm" then
				MirrorImageHandler.removeImage(rSource, rTarget);
				table.insert(rAction.aMessages, "[MIRROR IMAGE REMOVED BY NEAR MISS]");
			end
		end
	end
	
	-- KEL Save overlay
	if (rAction.sResult == "miss" or rAction.sResult == "fumble") and string.match(rRoll.sDesc, "%[ACTION%]") and rRoll.sType ~= "critconfirm" then
			TokenManager2.setSaveOverlay(ActorManager.getCTNode(rTarget), -3);
	elseif (rAction.sResult == "hit" or rAction.sResult == "crit") and string.match(rRoll.sDesc, "%[ACTION%]") and rRoll.sType ~= "critconfirm" then
		TokenManager2.setSaveOverlay(ActorManager.getCTNode(rTarget), -1);
	end
	-- END

	-- bmos adding automatic ammunition ticker and chat messaging
	if not rRoll.sDesc:match('%[CONFIRM%]') and (rRoll.sDesc:match('%[ATTACK %(R%)%]') or rRoll.sDesc:match('%[ATTACK #%d+ %(R%)%]')) then
		local sWeaponName = rRoll.sDesc;
		sWeaponName = sWeaponName:gsub('%[ATTACK %(R%)%]', '');
		sWeaponName = sWeaponName:gsub('%[ATTACK #%d+ %(R%)%]', '');
		sWeaponName = sWeaponName:gsub('%[.+%]', '');
		sWeaponName = StringManager.trim(sWeaponName);
		
		local nodeWeaponList = DB.findNode(rSource.sCreatureNode .. '.weaponlist');
		for _,v in pairs(nodeWeaponList.getChildren()) do
			if StringManager.trim(DB.getValue(v, 'name', '')) == sWeaponName then
				local nMaxAmmo = DB.getValue(v, 'maxammo', 0);
				local nAmmoUsed = DB.getValue(v, 'ammo', 0) + 1;
				
				if nMaxAmmo ~= 0 and not EffectManager35E.hasEffectCondition(rSource, 'INFAMMO') then
					if nAmmoUsed == nMaxAmmo then
						ChatManager.Message(string.format(Interface.getString('char_actions_usedallammo'), sWeaponName), true, rSource);
						DB.setValue(v, 'ammo', 'number', nAmmoUsed);
					else
						DB.setValue(v, 'ammo', 'number', nAmmoUsed);
					end
					
					if rAction.sResult == 'miss' or rAction.sResult == 'fumble' then -- bmos adding arrow recovery automation
						DB.setValue(v, 'missedshots', 'number', DB.getValue(v, 'missedshots', 0) + 1);
					end
				end
			end
		end
	end
	-- end bmos adding automatic ammunition ticker

	if rTarget then
		ActionAttack.notifyApplyAttack(rSource, rTarget, rRoll.bTower, rRoll.sType, rRoll.sDesc, rAction.nTotal, table.concat(rAction.aMessages, " "));
		
		-- REMOVE TARGET ON MISS OPTION
		if (rAction.sResult == "miss" or rAction.sResult == "fumble") and rRoll.sType ~= "critconfirm" and not string.match(rRoll.sDesc, "%[FULL%]") then
			local bRemoveTarget = false;
			if OptionsManager.isOption("RMMT", "on") then
				bRemoveTarget = true;
			elseif rRoll.bRemoveOnMiss then
				bRemoveTarget = true;
			end
			
			if bRemoveTarget then
				TargetingManager.removeTarget(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rTarget));
			end
		end
	end
	
	-- HANDLE FUMBLE/CRIT HOUSE RULES
	local sOptionHRFC = OptionsManager.getOption("HRFC");
	if rAction.sResult == "fumble" and ((sOptionHRFC == "both") or (sOptionHRFC == "fumble")) then
		ActionAttack.notifyApplyHRFC("Fumble");
	end
	if rAction.sResult == "crit" and ((sOptionHRFC == "both") or (sOptionHRFC == "criticalhit")) then
		ActionAttack.notifyApplyHRFC("Critical Hit");
	end
end