#!/usr/bin/env python
# Run Biomni A1 against MiniMax-M3 (Anthropic-compatible), counting every LLM call via callback.
import os, sys, json, time
RUN="/data/share/mouls/XenotransFormer/biomni_run"
ENVFILE=os.environ.get("BIOMNI_ENVFILE", f"{RUN}/.env")
MODEL=os.environ.get("BIOMNI_MODEL", "MiniMax-M3")
TAG=os.environ.get("BIOMNI_TAG", "run")
env={}
for line in open(ENVFILE):
    if "=" in line: k,v=line.strip().split("=",1); env[k]=v
os.environ["ANTHROPIC_BASE_URL"]=env["ANTHROPIC_BASE_URL"]
os.environ["ANTHROPIC_API_KEY"]=env["ANTHROPIC_API_KEY"]
print(f"=== backend: model={MODEL} base={env['ANTHROPIC_BASE_URL']} tag={TAG} ===", flush=True)

from langchain_core.callbacks import BaseCallbackHandler
from langchain_anthropic import ChatAnthropic

# --- MiniMax compat: its Anthropic-style responses can carry content=None (thinking model);
#     langchain_anthropic._format_output does `for block in content` -> crashes. Guard it. ---
import langchain_anthropic.chat_models as _ACM
_orig_format = _ACM.ChatAnthropic._format_output
def _safe_format(self, data, **kwargs):
    c = getattr(data, "content", "MISSING")
    if c is None:
        print(f"[MINIMAX content=None] stop_reason={getattr(data,'stop_reason',None)} "
              f"role={getattr(data,'role',None)}", flush=True)
        try: data.content = []
        except Exception:
            try: object.__setattr__(data, "content", [])
            except Exception: pass
    return _orig_format(self, data, **kwargs)
_ACM.ChatAnthropic._format_output = _safe_format

class CallCounter(BaseCallbackHandler):
    def __init__(self): self.n=0; self.in_tok=0; self.out_tok=0
    def on_chat_model_start(self, serialized, messages, **kw):
        self.n+=1; print(f"[LLM CALL #{self.n}]  in={self.in_tok} out={self.out_tok}", flush=True)
    def on_llm_end(self, response, **kw):
        try:
            g=response.generations[0][0]
            u=getattr(g.message,"usage_metadata",None) or {}
            self.in_tok+=u.get("input_tokens",0); self.out_tok+=u.get("output_tokens",0)
        except Exception: pass
CB=CallCounter()

def patched_get_llm(model=None, temperature=None, stop_sequences=None, source=None,
                    base_url=None, api_key=None, config=None):
    kw=dict(model=MODEL, base_url=env["ANTHROPIC_BASE_URL"], api_key=env["ANTHROPIC_API_KEY"],
            temperature=0.7 if temperature is None else temperature, max_tokens=8000, callbacks=[CB])
    try:
        return ChatAnthropic(stop_sequences=stop_sequences or None, **kw)
    except Exception as e:
        print("WARN stop_sequences ctor failed, retry without:", e, flush=True)
        return ChatAnthropic(**kw)

import biomni.llm as _L; _L.get_llm=patched_get_llm
import biomni.agent.a1 as _A1; _A1.get_llm=patched_get_llm

from biomni.agent import A1
import shutil
TARGET=os.environ.get("BIOMNI_TARGET",""); REP=os.environ.get("BIOMNI_REP","1")
if TARGET:
    WS=f"{RUN}/workspace/{TARGET}_rep{REP}"; os.makedirs(WS,exist_ok=True)
    shutil.copy(f"{RUN}/data_targets/target_{TARGET}.h5ad", f"{WS}/target.h5ad")
    H5AD=f"{WS}/target.h5ad"; OUT=f"{WS}/biomni_labels.csv"
    PROMPT=open(f"{RUN}/task_prompt_template.txt").read().replace("__H5AD__",H5AD).replace("__OUT__",OUT)
    TAG=f"{TARGET}_rep{REP}"
else:
    WS=f"{RUN}/workspace"; os.makedirs(WS,exist_ok=True)
    PROMPT=open(f"{RUN}/task_prompt.txt").read()
t0=time.time()
agent=A1(path=WS, llm=MODEL, source="Anthropic",
         use_tool_retriever=True, expected_data_lake_files=[])
print(f"=== AGENT READY tag={TAG} ws={WS} ===", flush=True)
try:
    log, out = agent.go(PROMPT)
except Exception as e:
    import traceback; traceback.print_exc()
    out=f"ERROR: {e}"
dt=time.time()-t0
res={"model":MODEL,"tag":TAG,"llm_calls":CB.n,"input_tokens":CB.in_tok,
     "output_tokens":CB.out_tok,"wall_sec":round(dt,1)}
print("=== DONE ===\n"+json.dumps(res,indent=2), flush=True)
json.dump(res, open(f"{RUN}/stats_{TAG}.json","w"), indent=2)
open(f"{RUN}/transcript_{TAG}.txt","w").write(str(out))
