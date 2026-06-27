from transformers import AutoTokenizer
from pathlib import Path

MODEL_ID = "Qwen/Qwen2.5-3B-Instruct"
PROMPT_PATH = Path("data/system_prompt.txt")

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
text = PROMPT_PATH.read_text(encoding="utf-8")

tokens = tokenizer.encode(text)

print(f"Characters: {len(text)}")
print(f"Tokens: {len(tokens)}")
print(f"Approx chars/token: {len(text) / len(tokens):.2f}")
