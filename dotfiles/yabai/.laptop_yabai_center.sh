#!/bin/bash

yabai -m window --toggle float 2>/dev/null || true

# Set the desired window size (laptop)
width=1400
height=1000

# Calculate the coordinates to center the window
# You can adjust these values based on your screen resolution and desired window size
screen_width=$(yabai -m query --displays --display | jq '.frame.w')
screen_height=$(yabai -m query --displays --display | jq '.frame.h')
x=$(echo "scale=0; ($screen_width - $width) / 2" | bc)
y=$(echo "scale=0; ($screen_height - $height) / 2" | bc)

# Resize and move the window
yabai -m window --resize abs:$width:$height
yabai -m window --move abs:$x:$y