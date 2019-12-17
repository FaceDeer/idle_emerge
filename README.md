The ``idle_emerge`` command acts similarly to the built in ``emergeblocks`` command, but with some modifications to its behaviour that make it useful for emerging large regions on a live server. Normally ``emergeblocks`` completely locks up the map database while it's running, which prevents players from moving around and performing actions. When a region is queued for emerging in ``idle_emerge``, map blocks will be emerged one at a time with an interruption between each emerge call to allow other ongoing map activities to be performed.

Multiple regions can be queued up in ``idle_emerge``, they will be acted on in the order in which they were queued.

Furthermore, map blocks will be emerged in a spiral pattern starting from the center of the region and spreading outward. The intention behind this pattern is to allow a server admin to queue up a large region around a spawn point to emerge and have the blocks that are closest to where the players will spawn emerge first. If you have slow mapgen you can use this emerge mod to make the game much more responsive for players by pre-generating terrain before they get there, rather than on the fly. Bear in mind that you're trading off disk space for this benefit.

Idle emerge tasks are saved and reloaded when the server starts up, so if you've mistakenly started a large emerge you'll need to manually remove it.

## Command parameters

The ``/idle_emerge`` command can be called with the following parameters:

* ``/idle_emerge`` - displays the emerge tasks that are currently running and queued to run in future
* ``/idle_emerge clear [<index>]`` - removes the emerge task indicated by the queue index number, or if no index number is given all emerge tasks will be removed.
* ``/idle_emerge (x, y, z) (x, y, z)`` - Sets up a new emerge task that will include all blocks within the region defined by the two vectors.
* ``/idle_emerge here [<radius>]`` - Sets up an emerge task centered on your current location, optionally with a radius provided.

## Settings

These settings are defined in the minetest.conf file, or via "all settings".

* ``idle_emerge_delay``: the number of seconds that Minetest will wait between finishing the previous emerge call and starting the next one. Note that setting this to 0 is fine, other map operations will still be able to interject themselves between emerge calls.

* ``idle_emerge_admin_check``: The idle_emerge operation will be suspended if there are any players on the server who do *not* have the "server" privilege. The idea behind this is to allow idle_emerge to use system resources only when nobody else is online to be bothered by any lag it might introduce. "server" users are assumed to be admins who will understand and accept any reduction of their playing experience that might be caused by this.