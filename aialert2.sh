#!/bin/bash

# BI Alert
function bialert {
  if (( $BIALERTLAST < `date +%s` )); then
    # Remove old alert file
    rm -f alerts/$CAMERA.jpg

    # Copy alert image to BI
    cp $CAMERA.jpg alerts

    # Send alert to BI
    curl "http://192.168.12.6:81/admin?trigger&camera=$CAMERA&user=$BIUSER&pw=$BIPW&memo=${CAPTION:${#1}+3}&jpeg=C:\\BlueIris\Alerts\\$CAMERA.jpg" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    BIALERTLAST=$(echo `date +%s`+$BIALERTCD | bc)
  fi
}

# Front Outside Lights Alert
function frontlightsalert {
  if (( $FRONTLIGHTSALERTLAST < `date +%s` )); then
    curl http://192.168.12.197/apps/api/98/devices/192/on?access_token=2829106d-1c57-4227-a14f-fee19c02a92c > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    FRONTLIGHTSALERTLAST=$(echo `date +%s`+$FRONTLIGHTSALERTCD | bc)
  fi
}

# Front Flowerbed Lights Alert
function fblightsalert {
  if (( $FBLIGHTSALERTLAST < `date +%s` )); then
    curl http://192.168.12.197/apps/api/56/devices/105/on?access_token=a64309de-400d-425d-86dc-47c15ef27eed > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    FBLIGHTSALERTLAST=$(echo `date +%s`+$FBLIGHTSALERTCD | bc)
  fi
}

# Telegram Alert
function telegramalert {
  if (( $TELEGRAMALERTLAST < `date +%s` )); then
    curl -F "caption=$CAPTION" -F "chat_id=$TGCID" -F "photo=@$CAMERA.jpg" https://api.telegram.org/bot"$TGBOT"/sendphoto > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    TELEGRAMALERTLAST=$(echo `date +%s`+$TELEGRAMALERTCD | bc)
  fi
}

# Check if dection is different from last detection
function isdetectiondifferent {
  # If previous photo doesn't exist create a generic one
  if [ ! -f "$CAMERA"_p.bmp ]; then
    convert -size 100x100 xc:white "$CAMERA"_p.bmp
  fi

  # Get sameness decimal from last sent image
  PHOTODIFF=`compare -metric NCC "$CAMERA".bmp "$CAMERA"_p.bmp null: 2>&1`

  # Convert decimal of sameness to percent of differentness
  PHOTODIFF=$(echo 100-$PHOTODIFF*100 | bc)

  # Make it an int so bash doesn't loose its god damned mind
  PHOTODIFF=`printf "%.0f" "$PHOTODIFF"`

  # So... is it differenty enough?
  if (( $PHOTODIFF > $PERCENTDIFFERENT )); then
    # Remove old previous file
    rm -f "$CAMERA"_p.bmp

    # Copy current to new previous file
    cp "$CAMERA".bmp "$CAMERA"_p.bmp

    echo 1 # yes
  else
    echo 0 # no
  fi
}

# Hit up Deepstack AI for some sweet sweet skynet goodness
function detect {
  # Delete old image and get new one
  rm -f "$CAMERA".jpg
  rm -f "$CAMERA".bmp
  wget "http://$BISERVER/image/$CAMERA?user=$BIUSER&pw=$BIPW&q=$BISSQ&s=$BISSS&decode=$BISID" -O "$CAMERA".jpg > /dev/null 2>&1

  # Convert to bmp and remove jpg
  convert "$CAMERA".jpg "$CAMERA".bmp
  rm -f "$CAMERA".jpg

  # Add mask if it exists
  if [ -f "$CAMERA"_mask.txt ]; then
      convert "$CAMERA".bmp -fill black -draw @"$CAMERA"_mask.txt "$CAMERA"_m.jpg
  else
      convert "$CAMERA".bmp "$CAMERA"_m.jpg
  fi

  # Delete old json and send masked image to Deepstack AI for detection
  rm -f "$CAMERA".json
  curl -F image=@"$CAMERA"_m.jpg http://${DSAISERVERLIST[$DSAISERV]}/v1/vision/detection -o "$CAMERA".json > /dev/null 2>&1

  # Get the number of found things
  THINGS=`jq '.predictions | length' "$CAMERA".json`

  # Set caption to camera name
  CAPTION=$CAMERA" - "

  # Iterate through each of the found things
  for (( i=0; i<$THINGS; i++ ))
  do
    # Get name of found thing 
    LABEL=`jq ".predictions[$i].label" "$CAMERA".json  | sed 's/"//g' | tr [:lower:] [:upper:]`

    # Iterate through THINGLIST
    for (( i2=0; i2<${#THINGLIST[@]}; i2=i2+2 ))
    do
      # Check if Found THING is something we want
      if [[ " ${THINGLIST[$i2]} " = " ${LABEL} " ]]; then
 
        # Get prediction confidence and mung it into an int
        CONFIDENCE=`jq ".predictions[$i].confidence" "$CAMERA".json`
        CONFIDENCE=${CONFIDENCE:2:2}
        
        # Check if found thing is high enough confidence
        if (( $CONFIDENCE > ${THINGLIST[$i2+1]} )); then
          # Add to caption
          CAPTION+=$LABEL" "$CONFIDENCE"% "

          # Get rectangle where found thing was found
          Y_MIN=`jq ".predictions[$i].y_min" "$CAMERA".json`
          X_MIN=`jq ".predictions[$i].x_min" "$CAMERA".json`
          Y_MAX=`jq ".predictions[$i].y_max" "$CAMERA".json`
          X_MAX=`jq ".predictions[$i].x_max" "$CAMERA".json`

          # Draw box around thing
          convert "$CAMERA".bmp -fill none -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_MAX,$Y_MAX" "$CAMERA".bmp

          # Figure out where the text will be and draw text background
          X_RECT=`convert -font helvetica -pointsize 18 label:"$LABEL $CONFIDENCE%" -format %w info:`
          X_RECT=$((X_MIN+X_RECT))
          Y_RECT=$((Y_MIN-16))
          convert "$CAMERA".bmp -fill red -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_RECT,$Y_RECT" "$CAMERA".bmp

          # Draw text
          convert "$CAMERA".bmp -font helvetica -pointsize 18 -draw "text $X_MIN,$Y_MIN '"$LABEL" "$CONFIDENCE"%'" "$CAMERA".bmp

          # Convert back to jpg
          convert "$CAMERA".bmp "$CAMERA".jpg
    
          # Alerts that fire on every detection
          # {
          if (( $BIALERT == 1 )); then
            # Send alert to BlueIris
            bialert
          fi

          if (( $FBLIGHTSALERT == 1 )); then
            # flowerbed lights
            fblightsalert
          fi

          if (( $FRONTLIGHTSALERT == 1 )); then
            # front lights
            frontlightsalert
          fi
          # }

          # Alerts that only fire when current and last detection are differenty enough
          # {
          if [ "$(isdetectiondifferent)" -eq 1 ]; then
            if (( $TELEGRAMALERT == 1 )); then
              # Telegram
              telegramalert
            fi
          fi
          # }
        fi
      fi
    done
  done
}

# Insert Vodka and press any key to continue
function loopy {
  # Set camera name
  CAMERA=$1

  # Load camera config
  . conf/$CAMERA.conf

  # Remove previous alert image
  rm -f "$CAMERA"_p.bmp
  # Prime alert timers
  TELEGRAMALERTLAST=0
  FBLIGHTSALERTLAST=0
  FRONTLIGHTSALERTLAST=0
  BIALERTLAST=0

  # Startup with a random Deepstack AI endpoint
  DSAISERV=$((0 + $RANDOM % ${#DSAISERVERLIST[@]}))

  ## Do things until the heat death of the universe
  while [ 1 ]
  do
    # Run detect function
    detect

    # Choose next Deepstack AI endpoint
    DSAISERV=$((DSAISERV+1))

    # Loop to first Deepstack AI endpoint if necessary
    if (( $DSAISERV >= ${#DSAISERVERLIST[@]} )); then
      DSAISERV=0
    fi
  
    # Reload camera config after every loop so changes to config are automatically picked up
    . conf/$CAMERA.conf

    # Sleep some every loop
    sleep $SLEEPSECONDS
  done &
}

#Cabin Creek
#loopy ipcamg1 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
#loopy ipcamg2 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
#loopy ipcamg3 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
#loopy ipcambd 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
#loopy ipcamsd 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
#loopy ipcamd1 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1
#loopy ipcamfd 100 100 -1 $CCID $TGBOT 1 30 5 1 1 1 1
#loopy ipcamlv 100 100 -1 $CCID $TGBOT 1 30 5 0 0 0 1
#loopy ipcamsw 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1
#loopy ipcamsg 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1

#Shamrock
#loopy DADBY 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
#loopy DADDB 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
#loopy DADDW 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
#loopy DADFD 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1

# Start camera threads for each camera config file found
for file in conf/*.conf; do
  filename=$(basename -- "$file")
  extension="${filename##*.}"
  filename="${filename%.*}"
  loopy $filename #camera name
done
