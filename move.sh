#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p history
compgen -G "output/*.txt" > /dev/null 2>&1 && mv output/*.txt history/
