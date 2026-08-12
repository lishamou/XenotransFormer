import os
env={}
for line in open("/data/share/mouls/XenotransFormer/biomni_run/.env"):
    if "=" in line: k,v=line.strip().split("=",1); env[k]=v
from langchain_anthropic import ChatAnthropic
llm=ChatAnthropic(model="MiniMax-M3", base_url=env["ANTHROPIC_BASE_URL"],
                  api_key=env["ANTHROPIC_API_KEY"], max_tokens=64, temperature=0)
r=llm.invoke("Reply with exactly one word: PONG")
print("ROUTED_OK content=", repr(r.content)[:120])
print("usage_metadata=", getattr(r,"usage_metadata",None))
