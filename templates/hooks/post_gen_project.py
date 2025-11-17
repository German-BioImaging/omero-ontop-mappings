import os
import stat
from pathlib import Path

def escape_jdbc_password(path: Path) -> None:
    if not path.exists():
        return

    lines = path.read_text().splitlines()
    new_lines = []

    for line in lines:
        if line.startswith("jdbc.password="):
            key, value = line.split("=", 1)
            # Escape '!' as '\!'
            value = value.replace("!", r"\!")
            new_lines.append(f"{key}={value}")
        else:
            new_lines.append(line)

    path.write_text("\n".join(new_lines) + "\n")

def main():
    # properties lives in the generated root
    props = Path("omero-ontop-mappings.properties")
    if props.exists():
        escape_jdbc_password(props)
        try:
            os.chmod(props, stat.S_IRUSR | stat.S_IWUSR)  # 600
            print(f"Set 600 on {props}")
        except Exception as e:
            print(f"Warning: could not chmod 600 on {props}: {e}")

if __name__ == "__main__":
    main()
