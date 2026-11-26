# Hailstone Suitcase

Carry a few sets of armor, jewelry, and weapons and switch between them from Hailstone. Suitcase remembers which exact items go in each slot. Your gear stays in your ordinary bags between swaps.

## Install

In Hailstone 0.7.3-beta or newer, open **Add-ons** from the login screen and add this repository. Approve Suitcase when prompted and use the **Modern** interface or a pack that inherits it. Your server must allow this add-on and its read, UI, actions, and commands permissions.

## Use it

1. Type `/suitcase` and equip the pieces you want to save.
2. Click **Save Equipped**, name the set, and click **Save Set**. Sets and the layout are saved for this character on this server.
3. Select a set in the sidebar. **Inventory** shows real item icons on a paper doll. **List** shows names and locations. Red icons identify gear that cannot be resolved. The detail tells you which item is missing or ambiguous.
4. Click **Equip Set**, or use `/suitcase "Set Name"`, `/equipset "Set Name"`, or `/suit "Set Name"`. Each command without a name opens the window. Names match without regard to case.

Click a slot to inspect it. Under **Edit Set**, **Use Worn** saves the item you’re currently wearing in that slot, **Set Empty** asks Suitcase to remove the item when equipping the set, and **Ignore Slot** leaves whatever you’re wearing alone. Use **Rename** or **Delete** to manage sets.

Click **Make Hotkey** to put a regular Hailstone social on your cursor, then place it in any normal hotbar slot. A set’s hotkey follows it when renamed. Deleting the set makes its old hotkey report that the set is unavailable.

## Swapping gear

Suitcase checks that the required pieces are equipped or carried, that it can resolve the right copy, and that displaced gear has room. It reuses the incoming item’s old bag slot where possible. Bring banked gear into your carried inventory before equipping the set. On older builds with less information about bags, free general inventory space can help when Suitcase can’t prove a bag will accept an outgoing item. Servers that use temporary item serials need a unique match after a relog. Newer Hailstone builds can include augment sockets in the match.

The game processes inventory moves individually. Keep your cursor clear and finish casting, trading, looting, or other inventory jobs before starting. Suitcase stops if state changes unexpectedly and reports partial progress. Use the regular inventory to finish placing anything that remains on your cursor.

## Build and test

Run `python tools/package.py` with the Hailstone client checkout next to this repository. The package is platform independent. Use Lua 5.4 to run the checks under `tests/` from the repository root.
