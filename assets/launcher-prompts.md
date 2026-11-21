# 首页插图 · 0.0.28

生成方式：内置 image_gen，原创蜡笔图，不复用参考网站素材或源码；无人物、品牌、白边或外框。场景色为麦黄、灰蓝与鼠尾草绿，暖灰笔触。四张原画随公开客户端打包，中间稿不入包。

布局：上排三个入口等宽，占窗口 60%；下排百宝箱整宽，占 40%。上排正方形原画，主体居中、周围有纸纹安全区；适配只裁外围纸纹，不裁主体，不悬停放大。下排为 3:1 横向浅抽屉。

初稿场景提示词：

[
  [
    "shell",
    "portrait 2:3",
    "a quiet terminal workbench: a small retro cream computer with only an abstract prompt glyph >_ on its screen, a green server tower, two folders linked by one cable; all main objects complete, centered low, no people",
    "warm muted ochre paper, sage objects, dark warm graphite outlines"
  ],
  [
    "data",
    "portrait 2:3",
    "a quiet data archive desk: three simple database cylinder stacks, small labeled-by-shape index drawers, a magnifying glass leaning against the front stack, paper index cards; all main objects complete, centered low; no actual words, no people",
    "dusty blue paper, sage and warm yellow objects, dark warm graphite outlines"
  ],
  [
    "git",
    "portrait 2:3",
    "a quiet version-history workshop: a freestanding paper board showing elegant branching colored rails with round commit nodes, small folder and pencil at its foot; all main objects complete, centered low; no actual words, no people",
    "muted sage paper, dusty blue and ochre branching rails, dark warm graphite outlines"
  ],
  [
    "toolbox",
    "very wide panoramic 3:1",
    "an open shallow wooden toolbox drawer seen gently from above, containing small tidy objects for text, clock, brackets, key, magnifying glass, two document sheets and a hash stamp; objects form a slender horizontal band in the center, complete silhouettes with roomy paper above and below; no people",
    "pale warm sage paper, cream wood, muted ochre and dusty blue objects, dark warm graphite outlines"
  ]
]

上排构图修订提示词（分别引用初稿）：

Recompose the provided crayon illustration for a SQUARE 1:1 app entrance tile. Keep exactly its object identity, full silhouettes and original warm muted palette/crayon texture. Remove the excessive empty upper half: center the complete object group vertically and horizontally, the group occupies about 75% of tile width and 70% height, with equal modest space above and below. For shell shorten table legs as necessary to fit all objects. No cropped objects, no characters/people/animals/mascots, no extra text, no logo. Background colored crayon paper reaches all four edges, absolutely no white margins or frame or rounded rectangle. Full bleed square composition, not a portrait canvas.

最终安全区修订（分别引用上排各自居中版本）：

Edit this square wax-crayon artwork ONLY to reduce the complete object group's scale, preserving every object, texture, palette, ratios and silhouette. All objects INCLUDING table legs, leaves, server, books and pencils must fit INSIDE the central 65% WIDTH and central 65% HEIGHT of the square. Center the whole group horizontally AND vertically. Outer 17.5% on EVERY side must be ONLY the same continuous colored crayon paper; no objects at edges. This is a responsive UI safe area requirement: it must tolerate cropping 15% on any edge without touching a single object. No people/animals/characters/logos/extra text, no border, no white, keep full bleed original colored paper with real grain. SQUARE 1:1 output.

资源：Resources/Entrances/{shell,data,git,text,toolbox}.png。

## 0.0.30 临时文本独立入口

内置 imagegen，以 data.png 仅作笔触/配色参考，生成 text.png，不复用其数据库主体。上排为四个等宽独立入口（Shell、数据、Git、临时文本）；高度不超过窗口 60%，窄窗以卡片宽高比不低于 0.72 收紧高度。主体中心安全区保留，下面整行百宝箱。

提示词：

Create ONE original SQUARE 1:1 wax-crayon and colored-pencil illustration for a quiet macOS temporary text / Markdown writing workspace entrance. The provided image is a STYLE REFERENCE ONLY: match its softly grainy colored paper, handmade graphite-brown contours, restrained muted ochre/sage/dusty-blue objects and gentle flat lighting. Do not copy its database cylinders, archive cabinet or magnifier. New subject: a small open cream notebook with a few abstract handwriting strokes, a sage-green fountain pen diagonally beside it, a single loose page with tiny abstract heading/paragraph/code-like marks, and a modest ochre paper clip. NO readable words, no labels, no computer UI. Whole object group centered both horizontally and vertically, entirely within CENTRAL 60% WIDTH and CENTRAL 60% HEIGHT, outer 20% on EVERY edge is only continuous softly textured pale dusty-peach paper. Preserve all notebook corners and full pen silhouette. The safe margin is essential because narrow entrance tiles crop background. Full bleed colored paper to every edge; NO white border, frame, card, rounded rectangle, glow or cast shadow. NO characters, humans, animals, mascots, franchise elements, brand logos or watermark. Calm, lightweight, youthful and understated, consistent with a hand-drawn developer workbench.

