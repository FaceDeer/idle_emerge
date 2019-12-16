The ``idle_emerge`` command acts similarly to the built in ``emergeblocks`` command, but with some modifications to its behaviour that make it useful for emerging large regions on a live server. Normally ``emergeblocks`` completely locks up the map database while it's running, which prevents players from moving around and performing actions. When a region is queued for emerging in idle_emerge, map blocks will be emerged one at a time with an interruption between each emerge call to allow other ongoing map activities to be performed.

Multiple regions can be queued up in idle_emerge, they will be acted on in the order in which they were queued.

Furthermore, map blocks will be emerged in a spiral pattern starting from the center of the region and spreading outward. The intention behind this pattern is to allow a server admin to queue up a large region around a spawn point to emerge and have the blocks that are closest to where the players will spawn emerge first. If you have slow mapgen you can use this emerge mod to make the game much more responsive for players by pre-generating terrain before they get there, rather than on the fly. Bear in mind that you're trading off disk space for this benefit.

## Settings

* emerge_delay: the number of seconds that Minetest will wait between finishing the previous emerge call and starting the next one. Note that setting this to 0 is fine, other map operations will still be able to interject themselves between emerge calls.

* check_for_non_admin_players: The idle_emerge operation will be suspended if there are any players on the server who do *not* have the "server" privilege. The idea behind this is to allow idle_emerge to use system resources only when nobody else is online to be bothered by any lag it might introduce. "server" users are assumed to be admins who will understand and accept any reduction of their playing experience that might be caused by this.