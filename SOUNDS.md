# Sounds

Bundled in `Resources/Sounds`, copied into the app by `build.sh`. Credits shown in the app: Sound › Sound Credits (`CREDITS.txt`).

| File | Source | Author | License |
|---|---|---|---|
| `snow-night` | [Quiet Winter Night Ambience](https://freesound.org/people/TSP-Talk/sounds/845502/) | TSP-Talk | CC0 |
| `snow-wind` | [Winter Wind 01c](https://freesound.org/people/klangfabrik/sounds/117513/) | klangfabrik | CC0 |
| `autumn-trees` | [Autumn wind grabbs the trees](https://freesound.org/people/straget/sounds/403764/) | straget | CC0 |
| `autumn-leaves` | [Autumn Wind and Dry Leaves](https://freesound.org/people/Stek59/sounds/457318/) | Stek59 | CC0 |
| `rain-leaves` | [Gentle rain on leaves with soft wind and suburban ambience](https://freesound.org/people/Garuda1982/sounds/757276/) | Garuda1982 | CC0 |
| `rain-window` | [Rain on Windows, Interior, A](https://freesound.org/people/InspectorJ/sounds/346642/) | InspectorJ | CC BY 4.0 |
| `thunder-1…3` | [Distant Thunder](https://freesound.org/people/richwise/sounds/361401/) | richwise | CC0 |
| `blossom-breeze` | [Forest Close Up Trees](https://freesound.org/people/Anya_Media/sounds/523389/) | Anya_Media | CC0 |
| `blossom-birds` | [Birds in Spring Scotland](https://freesound.org/people/BurghRecords/sounds/463903/) | BurghRecords | CC0 |
| `halloween-night` | [Crickets and Tawny Owl](https://freesound.org/people/raoul_slayer/sounds/203598/) | raoul_slayer | CC0 |
| `owl-1…2` | [Tawny owl hooting](https://freesound.org/people/Patrick_Corra/sounds/745208/) | Patrick_Corra | CC0 |
| `crow-1…2` | [Crow](https://freesound.org/people/Ambientsoundapp/sounds/537988/) | Ambientsoundapp | CC0 |

## Processing

48 kHz stereo; high-pass 25–150 Hz per sound to remove rumble; the calmest stretch of each recording (smallest
short-term loudness spread) cut into a 26–150 s loop whose last 4 s are equal-power crossfaded into its start;
beds normalised to −29…−32 LUFS, calls to −27…−29 LUFS, true peak ≤ −1.5 dBTP; AAC 128 kbps (`afconvert`).
Calls (thunder, owl, crow) are the loudest events of their recordings with fades in and out.

Only CC0 and CC BY are used: Pixabay and Mixkit licenses forbid redistributing the raw files, and this repository is public.
