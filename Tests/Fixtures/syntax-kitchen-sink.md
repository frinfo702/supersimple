# Syntax kitchen sink

Paste this body into a note. Caret-on-syntax reveals markers; click away to see the live preview. Mix: **bold**, *italic*, ***both***, `code`, a [link](https://github.com), math $e^{i\pi}+1=0$, and an autolink https://example.com.

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6 with **bold**, *italic*, and `code`

---

## Emphasis

Asterisk: *italic*, **bold**, ***bold italic***.
Underscore: _italic_, __bold__, ___bold italic___.
Nested: **bold with *italic* inside**.
Escaped so it stays literal: \*not italic\*, \`not code\`, \[not a link\].

~~strikethrough (`~~…~~`)~~ and ==highlight (`==…==`)== — these two only render if the highlight/strikethrough extensions are registered; otherwise they stay visible as markers.

Typing `-` `>` becomes an arrow: ->

## Inline code

Wrap a span in backticks: `let x = 1`. Stars inside code stay literal: `a * b * c`. Double-backtick for a backtick: `` `raw` ``.

## Links, wiki, images

Markdown link: [GitHub](https://github.com/frinfo702/supersimple)
Link with code in the label: [`NativeTextView`](https://developer.apple.com/documentation/appkit/nstextview)
Bare URL (autolink + favicon): https://www.apple.com
Incomplete (still typing): [unclosed](
Wiki link: [[Syntax kitchen sink]]
Unresolved wiki: [[Missing Note]]
Markdown image: ![alt text](https://upload.wikimedia.org/wikipedia/commons/thumb/3/31/Apple_logo_white.svg/200px-Apple_logo_white.svg.png)
Image embed (paste creates these): ![[pasted-image]]

## Lists

Bullet `-`:
- alpha
- bravo with **bold** and `code`
	- nested one tab (depth 1)
		- nested two tabs (depth 2)
			- nested three tabs (depth 3)
- wrap test — long unbreakable run should stay on the first line: https://example.com/this/is/a/very/long/path/that/must/not/drop/the/bullet/onto/its/own/line

Bullet `*` and `+`:
* star item
+ plus item

Ordered `1.` — nested display cycles 1 → a → i → 1:
1. first
2. second
	1. indented → a
	2. indented → b
		1. two tabs → i
		2. two tabs → ii
			1. three tabs → 1 again
3. third

Ordered `1)`:
1) paren one
2) paren two

Task list:
- [ ] unchecked
- [x] checked
- [ ] task with **bold**
	- [ ] nested task

Empty-looking continued item (type Enter on a list line to add another):
- trailing item

## Blockquotes

> Single-level quote with **bold** and a [link](https://example.com).
> Second line of the same quote.

>> Nested quote (depth 2).
>>> Depth 3.

> Quote that contains a list:
> - quoted bullet
> - another
> 1. quoted ordered

> Wrap test: https://example.com/another/very/long/unbreakable/url/inside/a/blockquote

## Code blocks

```swift
struct Note: Equatable {
    let id: UUID
    var title: String
    var body: String
}
```

```python
def greet(name: str) -> str:
    return f"hello, {name}"
```

```json
{ "ok": true, "count": 3 }
```

```
no language tag — plain fence
```

## LaTeX

Inline: the Gaussian $f(x)=\frac{1}{\sigma\sqrt{2\pi}}e^{-\frac{1}{2}(\frac{x-\mu}{\sigma})^2}$ in a sentence.

Display:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Aligned-ish block:

$$
\begin{aligned}
\nabla \times \mathbf{B} &= \mu_0\mathbf{J} + \mu_0\varepsilon_0\frac{\partial\mathbf{E}}{\partial t} \\
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0}
\end{aligned}
$$

## Tables

Narrow (inline markdown in cells):

| Align left | Center | Right |
| :--- | :---: | ---: |
| `alpha` | **bold** | 1 |
| *italic* | $a^2$ | 20 |
| [link](https://example.com) | ~~strike~~ | 300 |

Wide (should grow a horizontal scroller):

| Col A | Col B | Col C | Col D | Col E | Col F | Col G | Col H |
| --- | --- | --- | --- | --- | --- | --- | --- |
| lorem ipsum dolor sit amet | consectetur adipiscing elit | sed do eiusmod tempor | incididunt ut labore | et dolore magna aliqua | ut enim ad minim | veniam quis nostrud | exercitation ullamco |
| a | b | c | d | e | f | g | h |

## Thematic breaks

Hyphens:

---

Asterisks:

***

Underscores:

___

## Paragraphs

A normal paragraph after a blank line. Soft line wrapping should follow the reading column.

Two  spaces at the end of this line  
make a hard break (if the renderer treats trailing spaces as `<br>`).

Final paragraph with mixed leftovers: **bold**, _italic_, `code`, [[wiki]], $x_i$, https://example.org, and a list leftover:

- leftover bullet after prose

#syntax #kitchen-sink #markdown
