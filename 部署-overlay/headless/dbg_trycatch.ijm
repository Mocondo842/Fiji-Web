// does the macro language support try/catch?
LOG = "C:/Users/sr123/ijweb/headless/dbg_trycatch.log";
try {
  x = someUndefinedFunctionCall(1);
} catch (e) {
  File.append("caught: " + e.getMessage(), LOG);
}
File.append("after-try", LOG);
