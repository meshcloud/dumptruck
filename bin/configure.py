#!/usr/bin/env python3
import os

def main():
    # look for all env vars *_CONFIG_JSON and write them to *.config.json files
    for k in os.environ:
       if k.endswith('_CONFIG_JSON'):
            v = os.environ[k]
            name = k.lower().replace('_', '.')
            print("writing: %s" % name)

            with open(name, "w") as text_file:
                text_file.write(v)

if __name__ == "__main__":
    main()
