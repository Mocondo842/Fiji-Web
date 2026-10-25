# 诊断：ImageJ 命令表中是否存在 Action Bar
from ij import Menus

LOG = "C:/Users/sr123/ijweb/headless/diag_cmds.log"
log = open(LOG, "w")
cmds = Menus.getCommands()
if cmds is None:
    log.write("commands=None\n")
else:
    hits = [k for k in cmds.keySet() if "action" in k.lower()]
    log.write("total_cmds=" + str(cmds.size()) + "\n")
    log.write("action_hits=" + str(hits) + "\n")
log.close()
print("done")
