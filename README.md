# Ashwater Blog

A minimal static blog served from a Raspberry Pi Zero 2 W, featuring AI-generated daily stories.

**Live:** [blog.ashwater.ca](https://blog.ashwater.ca)

## Overview

Ashwater is a ~250-line bash static site generator that converts Markdown to HTML. The blog runs on a Raspberry Pi Zero 2 W behind a Cloudflare Tunnel, drawing about 0.5W of power.

Daily short stories are generated at 3am by a 15M parameter AI model (TinyStories) running locally on the Pi.

## Directory Structure

```
/var/www/blog/
├── build.sh              # Main static site generator
├── update-vitals.sh      # Updates live Pi stats (colophon, uptime)
├── posts/                # Blog posts (Markdown)
│   └── YYYY-MM-DD-slug.md
├── pi-stories/           # AI-generated stories (Markdown)
│   └── pi-story-YYYY-MM-DD.md
├── templates/
│   ├── header.html       # HTML head + nav template
│   └── footer.html       # Footer template (includes {{UPTIME}})
├── public/               # Generated output (served by lighttpd)
│   ├── index.html        # Homepage with post listing
│   ├── posts/            # Generated post HTML (gitignored)
│   ├── pi-stories/       # Generated story HTML + index
│   ├── style.css         # Site styles
│   ├── about.html        # About page
│   ├── colophon.html     # Live Pi vitals (generated)
│   ├── feed.xml          # RSS feed for posts
│   ├── feed-stories.xml  # RSS feed for pi-stories
│   ├── sitemap.xml       # Generated sitemap
│   ├── robots.txt        # Generated robots.txt
│   ├── uptime.txt        # Current uptime (for footer)
│   └── 404.html          # Custom 404 page
└── .gitignore
```

## Writing Posts

### Creating a New Post

1. Create a Markdown file in `posts/`:
   ```bash
   nano posts/YYYY-MM-DD-my-post-slug.md
   ```

2. Add frontmatter at the top:
   ```markdown
   ---
   title: My Post Title
   date: 2026-01-30
   description: Optional description for SEO/RSS
   ---

   Your content here in Markdown...
   ```

3. Build the site:
   ```bash
   BLOG_DOMAIN=blog.ashwater.ca ./build.sh
   ```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `title` | No | Post title (defaults to slug if omitted) |
| `date` | No | Publication date YYYY-MM-DD (defaults to file mtime) |
| `description` | No | SEO description (auto-generated from first paragraph if omitted) |

### File Naming Convention

Posts should be named: `YYYY-MM-DD-slug.md`

The date prefix is stripped from the URL, so `2026-01-30-hello-world.md` becomes `/posts/hello-world.html`.

## Building the Site

### Manual Build

```bash
cd /var/www/blog
BLOG_DOMAIN=blog.ashwater.ca ./build.sh
```

### What build.sh Does

1. Converts all `posts/*.md` to `public/posts/*.html`
2. Converts all `pi-stories/*.md` to `public/pi-stories/*.html`
3. Generates `public/index.html` (homepage with post listing)
4. Generates `public/pi-stories/index.html` (stories listing)
5. Generates `public/sitemap.xml`
6. Generates `public/robots.txt`
7. Generates `public/feed.xml` (RSS for posts)
8. Generates `public/feed-stories.xml` (RSS for stories)

### Dependencies

- **lowdown** - Markdown to HTML converter
  ```bash
  sudo apt install lowdown
  ```

## Cron Jobs

Three cron jobs automate the blog:

```crontab
# Pull from GitHub and rebuild every 5 minutes
*/5 * * * * cd /var/www/blog && git pull -q && BLOG_DOMAIN=blog.ashwater.ca ./build.sh > /dev/null 2>&1

# Generate AI story daily at 3am
0 3 * * * /home/mikhailst-laurent/generate-story.sh >> /var/log/pi-stories.log 2>&1

# Update live Pi vitals every 30 minutes
*/30 * * * * /var/www/blog/update-vitals.sh > /dev/null 2>&1
```

This means you can push changes to GitHub and they'll be live within 5 minutes.

## Remote Workflow (from another machine)

### Quick Commands

```bash
# SSH to the Pi
ssh mikhailst-laurent@mikhail-rpi.lan

# Create and edit a new post
ssh mikhailst-laurent@mikhail-rpi.lan "nano /var/www/blog/posts/2026-01-30-my-post.md"

# Build after editing
ssh mikhailst-laurent@mikhail-rpi.lan "cd /var/www/blog && BLOG_DOMAIN=blog.ashwater.ca ./build.sh"

# Commit and push
ssh mikhailst-laurent@mikhail-rpi.lan "cd /var/www/blog && git add -A && git commit -m 'Add new post' && git push"
```

## CSS Styling

The site uses a minimal dark theme with CSS variables:

```css
:root {
  --bg: #0a0a0a;       /* Background */
  --fg: #ffb000;       /* Primary text (amber) */
  --fg-dim: #cc8c00;   /* Dimmed text */
  --link: #00ff88;     /* Links (green) */
  --link-hover: #00ffaa;
}
```

Edit `public/style.css` to customize.

**Important:** After changing CSS, increment the version query string in `templates/header.html` to bust Cloudflare's cache:
```html
<link rel="stylesheet" href="/style.css?v=3">
```

## Templates

### header.html

Contains `<head>`, navigation, and `<main>` opening tag. Uses placeholders:
- `{{TITLE}}` - Page title
- `{{DESCRIPTION}}` - Meta description
- `{{OG_TYPE}}` - OpenGraph type (website/article)

### footer.html

Contains `</main>`, footer links, and closing tags. Uses:
- `{{UPTIME}}` - Replaced with current Pi uptime

## Pi Stories (AI Generation)

Daily stories are generated by `/home/mikhailst-laurent/generate-story.sh`:

1. Starts llama-server with the 15M TinyStories model
2. Picks a random story prompt
3. Generates ~250 tokens
4. Auto-generates a title from story content
5. Saves to `pi-stories/pi-story-YYYY-MM-DD.md`
6. Rebuilds the blog

### Manual Story Generation

```bash
/home/mikhailst-laurent/generate-story.sh
```

Check logs:
```bash
tail -f /var/log/pi-stories.log
```

## Live Vitals

`update-vitals.sh` runs every 30 minutes and updates:
- `public/colophon.html` - Full system stats page
- `public/uptime.txt` - Uptime string for footer
- `public/about.html` - Footer uptime

Stats shown: uptime, CPU temp, memory usage, load average, disk usage.

## Git Workflow

### What's Tracked

- `posts/*.md` - Blog posts
- `pi-stories/*.md` - AI stories
- `templates/*.html` - HTML templates
- `public/style.css` - Styles
- `public/pi-stories/*.html` - Generated story pages
- `public/about.html` - About page
- `public/404.html` - Error page
- `build.sh`, `update-vitals.sh` - Scripts
- Feed files, sitemap, robots.txt

### What's Gitignored

- `public/posts/` - Regenerated on build
- Editor backups (`*~`, `*.swp`)

### Pushing Changes

```bash
cd /var/www/blog
git add posts/my-new-post.md
git commit -m "Add post about XYZ"
git push
```

Or from remote:
```bash
ssh mikhailst-laurent@mikhail-rpi.lan "cd /var/www/blog && git add -A && git commit -m 'Message' && git push"
```

## Infrastructure

### Stack

| Component | Software |
|-----------|----------|
| Web Server | lighttpd |
| Tunnel | Cloudflare Tunnel (cloudflared) |
| SSL | Cloudflare (terminated at edge) |
| Build | Bash + lowdown |
| AI | llama.cpp + TinyStories-15M |

### Hardware

- Raspberry Pi Zero 2 W
- Quad-core ARM Cortex-A53 @ 1GHz
- 512MB RAM
- 64GB microSD
- ~0.5W idle power draw

## Troubleshooting

### CSS changes not appearing?
Cloudflare caches aggressively. Increment the version in `templates/header.html`:
```html
<link rel="stylesheet" href="/style.css?v=4">
```
Then rebuild.

### Build failing?
Check that lowdown is installed:
```bash
sudo apt install lowdown
```

### Posts not showing on homepage?
Ensure the post has valid frontmatter with `---` delimiters and rebuild.

### Story generation failing?
Check the log:
```bash
tail -50 /var/log/pi-stories.log
```
Common issues: model file missing, port 8082 in use.

## License

MIT
