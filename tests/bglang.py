"""The Bulgarian custom-field activity must retain Bulgarian prose and source tokens."""
import importlib.util
import json
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
english=json.loads((root/'i18n/data/en.jsn').read_text())
bulgarian=json.loads((root/'i18n/data/bg.jsn').read_text())
value=bulgarian['act-setCustomField'];prose=module.prose(value)
assert module.tokens(value)==module.tokens(english['act-setCustomField'])
assert not re.search(r'\b(?:је|изменио|рубрици|предмету|поступка|списима)\b',prose),prose
assert not any(char in prose for char in 'јЈљЉњЊћЋђЂџЏ')
assert re.search(r'\b(?:редактира[а-я]*|промен[а-я]+|актуализира[а-я]*|списъ[а-я]+|дъс[а-я]+|потребителск[а-я]+)\b',prose.lower())
assert len(re.findall(r'[а-яА-Я]',prose))>20
print('PASS: Bulgarian vocabulary, rejected Serbian seed markers and exact English placeholder inventory')
