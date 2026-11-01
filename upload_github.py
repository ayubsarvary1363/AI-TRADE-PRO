import ssl
import certifi
import os
import json
import base64
import getpass
import urllib.request
import urllib.error

OWNER = "ayubsarvary1363"
REPO = "AI-TRADE-PRO"

PROJECT = os.path.dirname(os.path.abspath(__file__))

SKIP_DIRS = {
    ".git", ".dart_tool", "build", ".idea", "__pycache__"
}

SKIP_FILES = {
    "local.properties"
}

def upload_file(token, filepath, relative_path):
    url = "https://api.github.com/repos/{}/{}/contents/{}".format(
        OWNER, REPO, relative_path.replace("\\", "/")
    )

    with open(filepath, "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")

    data = {
        "message": "Add project file: " + relative_path,
        "content": content
    }

    request = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "AI-Trade-Pro-Uploader"
        },
        method="PUT"
    )

    with urllib.request.urlopen(request, timeout=60, context=ssl.create_default_context(cafile=certifi.where())) as response:
        return response.status

def main():
    print("AI Trade Pro - GitHub Uploader")
    print("--------------------------------")

    token = getpass.getpass("GitHub Token (hidden): ")

    if not token:
        print("Token is empty.")
        return

    count = 0

    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        for filename in files:
            if filename in SKIP_FILES:
                continue

            filepath = os.path.join(root, filename)
            relative_path = os.path.relpath(filepath, PROJECT)

            try:
                status = upload_file(token, filepath, relative_path)
                print("Uploaded:", relative_path, status)
                count += 1

            except urllib.error.HTTPError as e:
                print("ERROR:", relative_path, e.code)
                print(e.read().decode("utf-8", "replace"))
                return

            except Exception as e:
                print("ERROR:", relative_path, str(e))
                return

    print("--------------------------------")
    print("Finished. Files uploaded:", count)

if __name__ == "__main__":
    main()
