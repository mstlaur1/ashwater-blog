#!/bin/bash
set -eu

export LC_ALL=C.UTF-8

BLOG_DIR="/var/www/blog"
POSTS_DIR="$BLOG_DIR/posts"
PI_STORIES_DIR="$BLOG_DIR/pi-stories"
PUBLIC_DIR="$BLOG_DIR/public"
TEMPLATES_DIR="$BLOG_DIR/templates"
DOMAIN="${BLOG_DOMAIN:-localhost}"

# Preflight check
if ! command -v lowdown &> /dev/null; then
    echo "Error: lowdown is required but not installed" >&2
    exit 1
fi

mkdir -p "$PUBLIC_DIR/posts"
mkdir -p "$PUBLIC_DIR/pi-stories"

# Get uptime for footer
get_uptime() {
    if [ -f "$PUBLIC_DIR/uptime.txt" ]; then
        cat "$PUBLIC_DIR/uptime.txt"
    else
        echo "starting..."
    fi
}

# Output footer with uptime
output_footer() {
    local uptime
    uptime=$(get_uptime)
    sed "s/{{UPTIME}}/uptime: $uptime/" "$TEMPLATES_DIR/footer.html"
}

# Check if file has frontmatter (starts with ---)
has_frontmatter() {
    head -1 "$1" | grep -q "^---$"
}

# HTML escape function
html_escape() {
    printf "%s" "$1" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\"/\&quot;/g"
}

# Strip newlines (sed operates line-by-line, newlines break substitution)
strip_newlines() {
    tr "\n" " "
}

# Safe sed substitution (escapes sed special chars)
sed_escape() {
    printf "%s" "$1" | sed "s/[&/\\]/\\\\&/g"
}

# Only parse frontmatter if file actually has it
parse_frontmatter() {
    local file="$1"
    local key="$2"
    if has_frontmatter "$file"; then
        sed -n "/^---$/,/^---$/p" "$file" | grep "^${key}:" | sed "s/^${key}: *//" | head -1
    fi
}

# Get content after frontmatter, or whole file if no frontmatter
get_content() {
    local file="$1"
    if has_frontmatter "$file"; then
        sed "1,/^---$/d" "$file"
    else
        cat "$file"
    fi
}

get_date_with_fallback() {
    local file="$1"
    local date
    date=$(parse_frontmatter "$file" "date")
    [ -z "$date" ] && date=$(date -r "$file" +%Y-%m-%d)
    printf "%s" "$date"
}

get_description() {
    local file="$1"
    local desc
    desc=$(parse_frontmatter "$file" "description")
    if [ -z "$desc" ]; then
        desc=$(get_content "$file" | grep -v "^$" | grep -v "^#" | head -1 | sed "s/[*_\`]//g")
        if [ "${#desc}" -gt 160 ]; then
            desc="${desc:0:157}..."
        fi
    fi
    printf "%s" "$desc"
}

get_slug() {
    basename "$1" .md | sed "s/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//"
}

# Calculate reading time (words / 200 wpm)
get_reading_time() {
    local file="$1"
    local words
    words=$(get_content "$file" | wc -w)
    local minutes=$(( (words + 199) / 200 ))
    [ "$minutes" -lt 1 ] && minutes=1
    printf "%d min read" "$minutes"
}

build_post() {
    local md_file="$1"
    local prev_slug="$2"
    local prev_title="$3"
    local next_slug="$4"
    local next_title="$5"
    local slug title date description html_file reading_time
    slug=$(get_slug "$md_file")
    title=$(parse_frontmatter "$md_file" "title")
    [ -z "$title" ] && title="$slug"
    date=$(get_date_with_fallback "$md_file")
    description=$(get_description "$md_file")
    reading_time=$(get_reading_time "$md_file")
    html_file="$PUBLIC_DIR/posts/${slug}.html"

    local title_html title_sed desc_html desc_sed canonical
    title_html=$(html_escape "$title" | strip_newlines)
    title_sed=$(sed_escape "$title_html")
    desc_html=$(html_escape "$description" | strip_newlines)
    desc_sed=$(sed_escape "$desc_html")

    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    canonical="${protocol}://${DOMAIN}/posts/${slug}.html"

    {
        sed -e "s/{{TITLE}}/$title_sed/g" \
            -e "s/{{DESCRIPTION}}/$desc_sed/g" \
            -e "s/{{OG_TYPE}}/article/g" \
            -e "s|{{CANONICAL}}|$canonical|g" \
            "$TEMPLATES_DIR/header.html"

        # Breadcrumb JSON-LD
        echo "<script type=\"application/ld+json\">"
        echo "{\"@context\":\"https://schema.org\",\"@type\":\"BreadcrumbList\",\"itemListElement\":["
        echo "{\"@type\":\"ListItem\",\"position\":1,\"name\":\"Home\",\"item\":\"${protocol}://${DOMAIN}/\"},"
        echo "{\"@type\":\"ListItem\",\"position\":2,\"name\":\"Posts\",\"item\":\"${protocol}://${DOMAIN}/posts/\"},"
        echo "{\"@type\":\"ListItem\",\"position\":3,\"name\":\"$title_html\"}"
        echo "]}</script>"

        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\">"
        echo "<a href=\"/\">~</a><span class=\"sep\">/</span><a href=\"/posts/\">posts</a><span class=\"sep\">/</span><span>$title_html</span>"
        echo "</nav>"

        echo "<article>"
        echo "<header>"
        echo "<h1>$title_html</h1>"
        echo "<p class=\"post-meta\"><time datetime=\"$date\">$date</time> · $reading_time</p>"
        echo "</header>"

        get_content "$md_file" | lowdown

        echo "</article>"

        # Prev/next navigation
        if [ -n "$prev_slug" ] || [ -n "$next_slug" ]; then
            echo "<nav class=\"post-nav\">"
            if [ -n "$prev_slug" ]; then
                echo "<a href=\"/posts/${prev_slug}.html\" class=\"prev\">← $prev_title</a>"
            else
                echo "<span></span>"
            fi
            if [ -n "$next_slug" ]; then
                echo "<a href=\"/posts/${next_slug}.html\" class=\"next\">$next_title →</a>"
            fi
            echo "</nav>"
        fi

        output_footer
    } > "$html_file"

    echo "Built: $html_file"
}

build_pi_story() {
    local md_file="$1"
    local slug title date description html_file
    slug=$(get_slug "$md_file")
    title=$(parse_frontmatter "$md_file" "title")
    [ -z "$title" ] && title="$slug"
    date=$(get_date_with_fallback "$md_file")
    description=$(get_description "$md_file")
    html_file="$PUBLIC_DIR/pi-stories/${slug}.html"

    local title_html title_sed desc_html desc_sed canonical
    title_html=$(html_escape "$title" | strip_newlines)
    title_sed=$(sed_escape "$title_html")
    desc_html=$(html_escape "$description" | strip_newlines)
    desc_sed=$(sed_escape "$desc_html")

    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    canonical="${protocol}://${DOMAIN}/pi-stories/${slug}.html"

    {
        sed -e "s/{{TITLE}}/$title_sed/g" \
            -e "s/{{DESCRIPTION}}/$desc_sed/g" \
            -e "s/{{OG_TYPE}}/article/g" \
            -e "s|{{CANONICAL}}|$canonical|g" \
            "$TEMPLATES_DIR/header.html"

        # Breadcrumb JSON-LD
        echo "<script type=\"application/ld+json\">"
        echo "{\"@context\":\"https://schema.org\",\"@type\":\"BreadcrumbList\",\"itemListElement\":["
        echo "{\"@type\":\"ListItem\",\"position\":1,\"name\":\"Home\",\"item\":\"${protocol}://${DOMAIN}/\"},"
        echo "{\"@type\":\"ListItem\",\"position\":2,\"name\":\"Pi Stories\",\"item\":\"${protocol}://${DOMAIN}/pi-stories/\"},"
        echo "{\"@type\":\"ListItem\",\"position\":3,\"name\":\"$title_html\"}"
        echo "]}</script>"

        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\">"
        echo "<a href=\"/\">~</a><span class=\"sep\">/</span><a href=\"/pi-stories/\">pi-stories</a><span class=\"sep\">/</span><span>$title_html</span>"
        echo "</nav>"

        echo "<article>"
        echo "<header>"
        echo "<h1>$title_html</h1>"
        echo "<time datetime=\"$date\">$date</time>"
        echo "</header>"

        get_content "$md_file" | lowdown

        echo "</article>"

        output_footer
    } > "$html_file"

    echo "Built: $html_file"
}

build_index() {
    local index_file="$PUBLIC_DIR/index.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    {
        sed -e "s/{{TITLE}}/Home/g" \
            -e "s/{{DESCRIPTION}}/Projects, planes, and parenthood. A tinkerer's journal from the Laurentians./g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/|g" \
            "$TEMPLATES_DIR/header.html"

        echo "<header class=\"hero\">"
        echo "<h1>Ashwater</h1>"
        echo "<p class=\"tagline\">Projects, planes, and parenthood.</p>"
        echo "</header>"

        echo "<section class=\"intro\">"
        echo "<p>Welcome. I'm Mikhail—father, airline pilot, and habitual tinkerer.</p>"
        echo "<p>This site is my journal: notes on self-hosting, aviation, fatherhood, and whatever else I'm building or breaking. It runs on a Raspberry Pi Zero 2 W drawing half a watt, because in an age of bloated frameworks and infinite cloud compute, there's something satisfying about creative constraints.</p>"
        echo "<p>No tracking. No JavaScript. Just words, served from a shelf in the Laurentians.</p>"
        echo "</section>"

        echo "<h2>Recent Posts</h2>"
        echo "<ul class=\"post-list\">"

        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            echo "${date}|${slug}|${title_html}"
        done | sort -r | head -5 | while IFS="|" read -r date slug title_html; do
            echo "<li><time datetime=\"$date\">$date</time> <a href=\"/posts/${slug}.html\">$title_html</a></li>"
        done

        echo "</ul>"
        echo "<p class=\"more-link\"><a href=\"/posts/\">All posts →</a></p>"

        # Subtle pi-stories section
        echo "<aside class=\"pi-stories-preview\">"
        echo "<h3>Latest Pi Story</h3>"
        echo "<p class=\"pi-stories-desc\">Daily tales from a 15M parameter AI running on the Pi.</p>"

        for md_file in "$PI_STORIES_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            echo "${date}|${slug}|${title_html}"
        done | sort -r | head -1 | while IFS="|" read -r date slug title_html; do
            echo "<p><a href=\"/pi-stories/${slug}.html\">$title_html</a> <span class=\"date\">($date)</span></p>"
        done

        echo "<p class=\"more-link\"><a href=\"/pi-stories/\">All stories →</a></p>"
        echo "</aside>"

        output_footer
    } > "$index_file"

    echo "Built: $index_file"
}

build_posts_index() {
    local index_file="$PUBLIC_DIR/posts/index.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    {
        sed -e "s/{{TITLE}}/Posts/g" \
            -e "s/{{DESCRIPTION}}/All posts from Ashwater - projects, aviation, self-hosting, and more/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/posts/|g" \
            "$TEMPLATES_DIR/header.html"

        echo "<header class=\"hero\">"
        echo "<h1>Posts</h1>"
        echo "<p>Everything I've written, newest first.</p>"
        echo "</header>"
        echo "<ul class=\"post-list\">"

        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            echo "${date}|${slug}|${title_html}"
        done | sort -r | while IFS="|" read -r date slug title_html; do
            echo "<li><time datetime=\"$date\">$date</time> <a href=\"/posts/${slug}.html\">$title_html</a></li>"
        done

        echo "</ul>"

        output_footer
    } > "$index_file"

    echo "Built: $index_file"
}

build_pi_stories_index() {
    local index_file="$PUBLIC_DIR/pi-stories/index.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    {
        sed -e "s/{{TITLE}}/Pi Stories/g" \
            -e "s/{{DESCRIPTION}}/Daily short stories generated by a 15M parameter AI running on a Raspberry Pi Zero 2 W/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/pi-stories/|g" \
            "$TEMPLATES_DIR/header.html"

        echo "<header class=\"hero\">"
        echo "<h1>Pi Stories</h1>"
        echo "<p>Daily short stories generated by a 15M parameter AI running on a Raspberry Pi Zero 2 W at 3am.</p>"
        echo "</header>"
        echo "<h2>Stories</h2>"
        echo "<ul class=\"post-list\">"

        for md_file in "$PI_STORIES_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            echo "${date}|${slug}|${title_html}"
        done | sort -r | while IFS="|" read -r date slug title_html; do
            echo "<li><time datetime=\"$date\">$date</time> <a href=\"/pi-stories/${slug}.html\">$title_html</a></li>"
        done

        echo "</ul>"

        output_footer
    } > "$index_file"

    echo "Built: $index_file"
}

build_sitemap() {
    local sitemap_file="$PUBLIC_DIR/sitemap.xml"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    
    {
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        echo "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
        echo "  <url><loc>${protocol}://${DOMAIN}/</loc></url>"
        echo "  <url><loc>${protocol}://${DOMAIN}/posts/</loc></url>"
        echo "  <url><loc>${protocol}://${DOMAIN}/pi-stories/</loc></url>"
        
        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug date
            slug=$(get_slug "$md_file")
            date=$(get_date_with_fallback "$md_file")
            echo "  <url>"
            echo "    <loc>${protocol}://${DOMAIN}/posts/${slug}.html</loc>"
            echo "    <lastmod>${date}</lastmod>"
            echo "  </url>"
        done
        
        for md_file in "$PI_STORIES_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug date
            slug=$(get_slug "$md_file")
            date=$(get_date_with_fallback "$md_file")
            echo "  <url>"
            echo "    <loc>${protocol}://${DOMAIN}/pi-stories/${slug}.html</loc>"
            echo "    <lastmod>${date}</lastmod>"
            echo "  </url>"
        done
        
        echo "</urlset>"
    } > "$sitemap_file"
    
    echo "Built: $sitemap_file"
}

build_robots() {
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    cat > "$PUBLIC_DIR/robots.txt" << EOF
User-agent: *
Allow: /

Sitemap: ${protocol}://${DOMAIN}/sitemap.xml
EOF
    echo "Built: $PUBLIC_DIR/robots.txt"
}

build_rss() {
    local rss_file="$PUBLIC_DIR/feed.xml"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    {
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        echo "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">"
        echo "<channel>"
        echo "  <title>Ashwater</title>"
        echo "  <link>${protocol}://${DOMAIN}/</link>"
        echo "  <description>A minimal blog about self-hosting, Linux, and tinkering with technology</description>"
        echo "  <atom:link href=\"${protocol}://${DOMAIN}/feed.xml\" rel=\"self\" type=\"application/rss+xml\"/>"

        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title date description
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            date=$(get_date_with_fallback "$md_file")
            description=$(get_description "$md_file")
            title=$(printf "%s" "$title" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            description=$(printf "%s" "$description" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            echo "${date}|${slug}|${title}|${description}"
        done | sort -r | while IFS="|" read -r date slug title description; do
            echo "  <item>"
            echo "    <title>$title</title>"
            echo "    <link>${protocol}://${DOMAIN}/posts/${slug}.html</link>"
            echo "    <guid>${protocol}://${DOMAIN}/posts/${slug}.html</guid>"
            echo "    <pubDate>$(date -d "$date" -R 2>/dev/null || echo "$date")</pubDate>"
            echo "    <description>$description</description>"
            echo "  </item>"
        done

        echo "</channel>"
        echo "</rss>"
    } > "$rss_file"

    echo "Built: $rss_file"
}

build_stories_rss() {
    local rss_file="$PUBLIC_DIR/feed-stories.xml"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    {
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        echo "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">"
        echo "<channel>"
        echo "  <title>Ashwater - Pi Stories</title>"
        echo "  <link>${protocol}://${DOMAIN}/pi-stories/</link>"
        echo "  <description>Daily short stories generated by a 15M parameter AI running on a Raspberry Pi Zero 2 W</description>"
        echo "  <atom:link href=\"${protocol}://${DOMAIN}/feed-stories.xml\" rel=\"self\" type=\"application/rss+xml\"/>"

        for md_file in "$PI_STORIES_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title date description
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            date=$(get_date_with_fallback "$md_file")
            description=$(get_description "$md_file")
            title=$(printf "%s" "$title" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            description=$(printf "%s" "$description" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            echo "${date}|${slug}|${title}|${description}"
        done | sort -r | while IFS="|" read -r date slug title description; do
            echo "  <item>"
            echo "    <title>$title</title>"
            echo "    <link>${protocol}://${DOMAIN}/pi-stories/${slug}.html</link>"
            echo "    <guid>${protocol}://${DOMAIN}/pi-stories/${slug}.html</guid>"
            echo "    <pubDate>$(date -d "$date" -R 2>/dev/null || echo "$date")</pubDate>"
            echo "    <description>$description</description>"
            echo "  </item>"
        done

        echo "</channel>"
        echo "</rss>"
    } > "$rss_file"

    echo "Built: $rss_file"
}

echo "Building blog..."

# Build posts with prev/next navigation
# First, collect all posts sorted by date (newest first)
declare -a POST_FILES POST_SLUGS POST_TITLES
i=0
while IFS="|" read -r date file slug title; do
    POST_FILES[$i]="$file"
    POST_SLUGS[$i]="$slug"
    POST_TITLES[$i]="$title"
    ((i++)) || true
done < <(
    for md_file in "$POSTS_DIR"/*.md; do
        [ -f "$md_file" ] || continue
        slug=$(get_slug "$md_file")
        title=$(parse_frontmatter "$md_file" "title")
        [ -z "$title" ] && title="$slug"
        date=$(get_date_with_fallback "$md_file")
        printf "%s|%s|%s|%s\n" "$date" "$md_file" "$slug" "$title"
    done | sort -r
)

# Build each post with prev/next links
for ((i=0; i<${#POST_FILES[@]}; i++)); do
    prev_slug="" prev_title="" next_slug="" next_title=""
    # Previous = newer post (lower index)
    if [ $i -gt 0 ]; then
        prev_slug="${POST_SLUGS[$((i-1))]}"
        prev_title="${POST_TITLES[$((i-1))]}"
    fi
    # Next = older post (higher index)
    if [ $((i+1)) -lt ${#POST_FILES[@]} ]; then
        next_slug="${POST_SLUGS[$((i+1))]}"
        next_title="${POST_TITLES[$((i+1))]}"
    fi
    build_post "${POST_FILES[$i]}" "$prev_slug" "$prev_title" "$next_slug" "$next_title"
done

for md_file in "$PI_STORIES_DIR"/*.md; do
    [ -f "$md_file" ] || continue
    build_pi_story "$md_file"
done

build_index
build_posts_index
build_pi_stories_index
build_sitemap
build_robots
build_rss
build_stories_rss

echo "Done!"
