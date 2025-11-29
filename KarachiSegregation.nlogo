extensions [ gis csv ]

globals [
  ; --- Datasets ---
  karachi-dataset-district
  karachi-dataset-UCS

  ; --- Parameters ---
  ; scaling-factor      ; Controls population density
  scan-radius         ; How far to look for neighbors
  sample-size         ; How many spots to check when moving
]

patches-own [
  town-name           ; Invisible logic: helps agents know where they are
]

turtles-own [
  linguistic-group    ; "Urdu", "Sindhi", "Pashto", "Other"
  religious-group     ; "Muslim", "Hindu", "Christian"
  current-utility     ; Happiness score (0.0 to 1.0)
]

; =================================================================
; 1. SETUP & VISUALIZATION (The "Clean" Look)
; =================================================================

to setup
  clear-all

  ; --- Defaults ---
  set scaling-factor 2000    ; 1 Agent = 2000 People (Adjust for performance)
  set scan-radius 3.0
  set sample-size 5

  ; --- Load Files ---
  ifelse file-exists? "Kar_UCS.shp" and file-exists? "kda.shp" [
    set karachi-dataset-district gis:load-dataset "kda.shp"
    set karachi-dataset-UCS gis:load-dataset "Kar_UCS.shp"
  ] [ user-message "Error: Shapefiles not found." stop ]

  ; --- Set Coordinate System ---
  gis:set-world-envelope (gis:envelope-of karachi-dataset-UCS)

  ; --- Draw the Clean Vector Map ---
  visualize-divisions

  ; --- Spawn Agents from Data ---
  ifelse file-exists? "karachi_data.csv" [
    spawn-population
  ] [ user-message "Error: karachi_data.csv not found." stop ]

  reset-ticks
end

to visualize-divisions
  print "--- DRAWING VECTOR MAP ---"

  ; 1. Background: Keep patches BLACK so the map looks sharp
  ask patches [ set pcolor black ]

  ; 2. Draw Towns (The Colorful Vector Layer)
  foreach gis:feature-list-of karachi-dataset-UCS [ feature ->
    let t-name gis:property-value feature "TOWN_NAMES"

    ; A. LOGIC: Tell the patches underneath who they are (Invisible)
    ask patches with [gis:intersects? feature self] [
      set town-name t-name
    ]

    ; B. VISUALS: Pick a distinct color for the Town
    ; FIX: Pick a base color first, THEN scale it.
    let base-color one-of [ red orange brown green cyan violet magenta blue ]

    ; Scale it to be slightly darker (5 out of 10) so agents pop
    gis:set-drawing-color scale-color base-color 5 0 10
    gis:fill feature 1.0  ; Smooth, solid fill

    ; C. BORDERS: Draw thin black lines between towns for clarity
    gis:set-drawing-color black
    gis:draw feature 1.0
  ]

  ; 3. Draw District Boundaries (Thick White Lines on top)
  gis:set-drawing-color white
  gis:draw karachi-dataset-district 2.0
end

; =================================================================
; 2. DATA LOADING & SPAWNING (The "Brains")
; =================================================================

to spawn-population
  print "--- SPAWNING POPULATION ---"
  let census-list csv:from-file "karachi_data.csv"

  foreach but-first census-list [ row ->
    ; 1. Get Town Name & Resolve to Shapefile Name
    let raw-name item 1 row
    let shapefile-name resolve-town-name raw-name

    ; 2. Find Valid Ground
    ; We look for patches tagged with this town name
    let town-patches patches with [town-name = shapefile-name]

    if count town-patches > 0 [
      let total-pop item 2 row
      let num-agents floor (total-pop / scaling-factor)

      if num-agents > 0 [
        repeat num-agents [
          ; Spawn on a random patch in the town
          ask one-of town-patches [
            sprout 1 [
              ; --- VISUALS: JITTER ---
              ; This prevents the "grid look". We move random amounts off-center.
              setxy (xcor + random-float 0.9 - 0.45) (ycor + random-float 0.9 - 0.45)

              set size 0.7         ; Nice visible size
              set shape "circle"

              ; --- IDENTITY: LINGUISTICS ---
              let pop-urdu item 3 row
              let pop-sindhi item 4 row
              let pop-pashto item 5 row
              let total item 2 row
              let rand-l random-float 1.0

              ifelse rand-l < (pop-urdu / total) [ set linguistic-group "Urdu" set color blue ]
              [ ifelse rand-l < ((pop-urdu + pop-sindhi) / total) [ set linguistic-group "Sindhi" set color red ]
                [ ifelse rand-l < ((pop-urdu + pop-sindhi + pop-pashto) / total) [ set linguistic-group "Pashto" set color green ]
                  [ set linguistic-group "Other" set color grey ]
                ]
              ]

              ; --- IDENTITY: RELIGION ---
              let pop-muslim item 6 row
              let pop-hindu item 7 row
              let rand-r random-float 1.0

              ifelse rand-r < (pop-muslim / total) [ set religious-group "Muslim" ]
              [ ifelse rand-r < ((pop-muslim + pop-hindu) / total) [ set religious-group "Hindu" ]
                [ set religious-group "Christian" ]
              ]

              update-utility
            ]
          ]
        ]
      ]
    ]
  ]
  print "--- SPAWNING COMPLETE ---"
end

; =================================================================
; 3. SIMULATION LOGIC (Simple Schelling)
; =================================================================

to go
  ; Move a small % of unhappy people each tick
  ask turtles with [current-utility < 0.5] [
    ; Only 10% chance to actually try moving this tick (simulates friction)
    if random-float 1.0 < 0.1 [
      find-new-home
    ]
  ]
  tick
end

to update-utility
  ; Are my neighbors like me?
  let neighbors-list (turtles-on patch-here) ; Check who is stacked with me

  ; If I'm alone on this patch, check radius
  if count neighbors-list <= 1 [
    set neighbors-list turtles in-radius scan-radius
  ]

  let total count neighbors-list
  if total <= 1 [ set current-utility 1.0 stop ] ; Happy if alone

  let similar 0
  ask neighbors-list [
    ; Similarity = Same Language OR Same Religion
    if (linguistic-group = [linguistic-group] of myself) or
       (religious-group = [religious-group] of myself)
       [ set similar similar + 1 ]
  ]

  set current-utility (similar / total)
end

to find-new-home
  ; Check 'sample-size' random spots. If one is better, move.
  let best-spot patch-here
  let best-util current-utility

  repeat sample-size [
    ; Pick a random patch that belongs to a town (not ocean)
    let candidate one-of patches with [town-name != 0]

    if candidate != nobody [
      ; Hypothetical: What if I moved there?
      let n-list turtles in-radius scan-radius ; Look at neighbors there
      let total count n-list
      let sim 0

      if total > 0 [
        ask n-list [
           if (linguistic-group = [linguistic-group] of myself) or
              (religious-group = [religious-group] of myself)
              [ set sim sim + 1 ]
        ]
        let util (sim / total)

        if util > best-util [
          set best-util util
          set best-spot candidate
        ]
      ]
    ]
  ]

  if best-spot != patch-here [
    move-to best-spot
    ; Jitter again on arrival so we don't stack perfectly
    setxy (xcor + random-float 0.9 - 0.45) (ycor + random-float 0.9 - 0.45)
    update-utility
  ]
end

; =================================================================
; 4. HELPERS
; =================================================================

to-report resolve-town-name [ csv-name ]
  ; Simple manual map to ensure CSV names match Shapefile names
  if csv-name = "Gulberg" [ report "GULBERG TOWN" ]
  if csv-name = "Liaquatabad" [ report "LIAQUATABAD TOWN" ]
  if csv-name = "Nazimabad" [ report "LIAQUATABAD TOWN" ]
  if csv-name = "New Karachi" [ report "NEW KARACHI TOWN" ]
  if csv-name = "North Nazimabad" [ report "NORTH NAZIMABAD TOWN" ]
  if csv-name = "Ferozabad" [ report "JAMSHED TOWN" ]
  if csv-name = "Gulshan-e-Iqbal" [ report "GULSHAN-E-IQBAL" ]
  if csv-name = "Gulzar-e-Hijri" [ report "GULSHAN-E-IQBAL" ]
  if csv-name = "Jamshed Quarters" [ report "JAMSHED TOWN" ]
  if csv-name = "Aram Bagh" [ report "SADDAR TOWN" ]
  if csv-name = "Civil Lines" [ report "SADDAR TOWN" ]
  if csv-name = "Garden" [ report "SADDAR TOWN" ]
  if csv-name = "Lyari" [ report "LAYARI TOWN" ]
  if csv-name = "Saddar" [ report "SADDAR TOWN" ]
  if csv-name = "Manghopir" [ report "GADAP TOWN" ]
  if csv-name = "Mominabad" [ report "ORANGI TOWN" ]
  if csv-name = "Orangi" [ report "ORANGI TOWN" ]
  if csv-name = "Baldia" [ report "BALDIA TOWN" ]
  if csv-name = "Keamari" [ report "KIAMARI TOWN" ]
  if csv-name = "Mauripur" [ report "KIAMARI TOWN" ]
  if csv-name = "SITE" [ report "S.I.T.E. TOWN" ]
  if csv-name = "Airport" [ report "SHAH FAISAL TOWN" ]
  if csv-name = "Bin Qasim" [ report "BIN QASIM TOWN" ]
  if csv-name = "Gadap" [ report "GADAP TOWN" ]
  if csv-name = "Ibrahim Hydri" [ report "BIN QASIM TOWN" ]
  if csv-name = "Murad Memon" [ report "GADAP TOWN" ]
  if csv-name = "Shah Mureed" [ report "GADAP TOWN" ]
  if csv-name = "Korangi" [ report "KORANGI TOWN" ]
  if csv-name = "Landhi" [ report "LANDHI TOWN" ]
  if csv-name = "Model Colony" [ report "MALIR TOWN" ]
  if csv-name = "Shah Faisal" [ report "SHAH FAISAL TOWN" ]
  if csv-name = "Malir" [ report "MALIR TOWN" ]
  report csv-name
end
@#$#@#$#@
GRAPHICS-WINDOW
223
10
1203
992
-1
-1
14.97
1
10
1
1
1
0
0
0
1
-32
32
-32
32
0
0
1
ticks
30.0

BUTTON
31
46
95
79
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
37
247
175
292
karachi-dataset
karachi-dataset
"Kar_UCS.shp" "kda.shp"
0

SLIDER
28
140
200
173
scaling-factor
scaling-factor
100
5000
2000.0
10
1
NIL
HORIZONTAL

SLIDER
32
197
204
230
noise-beta
noise-beta
0
20
20.0
1
1
NIL
HORIZONTAL

MONITOR
12
341
106
386
Average utility
mean [current-utility] of turtles
2
1
11

PLOT
0
396
200
546
Segregation over time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [current-utility] of turtles"

BUTTON
140
53
203
86
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
