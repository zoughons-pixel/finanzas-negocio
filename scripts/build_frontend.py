"""One source for the browser and Android's self-contained, offline-ready HTML."""
from pathlib import Path
import hashlib, json, re, shutil

ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'web'
dist=ROOT/'dist'
dist.mkdir(exist_ok=True)
for item in source.iterdir():
    target=dist/item.name
    if item.is_dir(): shutil.copytree(item,target,dirs_exist_ok=True)
    else: shutil.copy2(item,target)
html=(source/'index.html').read_text()
html=re.sub(r'<script src="([^"]+)"></script>',lambda m:'<script>'+ (source/m[1]).read_text().replace('</script','<\\/script')+'</script>' if (source/m[1]).is_file() else m[0],html)
html=re.sub(r'<link rel="stylesheet" href="([^"]+\.css)">',lambda m:'<style>'+ (source/m[1]).read_text()+'</style>' if (source/m[1]).is_file() else m[0],html)
html=re.sub(r'<link rel="(?:manifest|icon)"[^>]+>','',html)
assets=ROOT/'android/app/src/main/assets';assets.mkdir(exist_ok=True,parents=True)
(assets/'index.html').write_text(html)
output=ROOT/'release';output.mkdir(exist_ok=True)
(output/'frontend-2.1.2.html').write_text(html)
(output/'frontend-2.1.2.json').write_text(json.dumps({'version':'2.1.2','version_code':12,'sha256':hashlib.sha256(html.encode()).hexdigest()},indent=2)+'\n')
print('Built web and self-contained Android frontend:',len(html.encode()),'bytes')
