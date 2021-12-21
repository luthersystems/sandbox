#!/usr/bin/env bash

if [ -n $(which time) ]; then
    UNAME=$(uname)
    if [ "$UNAME" == "Linux" ]; then
        sudo apt-get install time
    elif [ "$UNAME" == "Darwin"]; then
        brew install time
    else
        sudo apt-get install time
    fi
fi