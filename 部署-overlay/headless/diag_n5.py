# find N5/Zarr related commands in Fiji command table
from ij import Menus

LOG = "C:/Users/sr123/ijweb/headless/diag_n5.log"
log = open(LOG, "w")
cmds = Menus.getCommands()
if cmds is None:
    log.write("commands=None\n")
else:
    for k in cmds.keySet():
        kl = k.lower()
        if "n5" in kl or "zarr" in kl:
            log.write(k + " => " + str(cmds.get(k)) + "\n")
log.close()
print("done")
