#!/bin/bash
set -eu

export LC_ALL=C.UTF-8

BLOG_DIR="/var/www/blog"
POSTS_DIR="$BLOG_DIR/posts"
PUBLIC_DIR="$BLOG_DIR/public"
TEMPLATES_DIR="$BLOG_DIR/templates"
DOMAIN="${BLOG_DOMAIN:-localhost}"

# Preflight check
if ! command -v lowdown &> /dev/null; then
    echo "Error: lowdown is required but not installed" >&2
    exit 1
fi

mkdir -p "$PUBLIC_DIR/posts"

# Check if file has frontmatter (starts with ---)
has_frontmatter() {
    head -1 "$1" | grep -q '^---$'
}

# HTML escape function
html_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# Strip newlines (sed operates line-by-line, newlines break substitution)
strip_newlines() {
    tr '\n' ' '
}

# Safe sed substitution (escapes sed special chars)
sed_escape() {
    printf '%s' "$1" | sed 's/[&/\]/\\&/g'
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
        sed '1,/^---$/d' "$file"
    else
        cat "$file"
    fi
}

get_date_with_fallback() {
    local file="$1"
    local date
    date=$(parse_frontmatter "$file" "date")
    [ -z "$date" ] && date=$(date -r "$file" +%Y-%m-%d)
    printf '%s' "$date"
}

get_description() {
    local file="$1"
    local desc
    desc=$(parse_frontmatter "$file" "description")
    if [ -z "$desc" ]; then
        desc=$(get_content "$file" | grep -v "^$" | grep -v "^#" | head -1 | sed 's/[*_`]//g')
        if [ "${#desc}" -gt 160 ]; then
            desc="${desc:0:157}..."
        fi
    fi
    printf '%s' "$desc"
}

get_slug() {
    basename "$1" .md | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'
}

build_post() {
    local md_file="$1"
    local slug title date description html_file
    slug=$(get_slug "$md_file")
    title=$(parse_frontmatter "$md_file" "title")
    # Fallback title to slug if no frontmatter
    [ -z "$title" ] && title="$slug"
    date=$(get_date_with_fallback "$md_file")
    description=$(get_description "$md_file")
    html_file="$PUBLIC_DIR/posts/${slug}.html"
    
    # Escape for HTML, strip newlines, then escape for sed
    local title_html title_sed desc_html desc_sed
    title_html=$(html_escape "$title" | strip_newlines)
    title_sed=$(sed_escape "$title_html")
    desc_html=$(html_escape "$description" | strip_newlines)
    desc_sed=$(sed_escape "$desc_html")
    
    {
        sed -e "s/{{TITLE}}/$title_sed/g" \
            -e "s/{{DESCRIPTION}}/$desc_sed/g" \
            -e "s/{{OG_TYPE}}/article/g" \
            "$TEMPLATES_DIR/header.html"
        
        echo "<article>"
        echo "<header>"
        echo "<h1>$title_html</h1>"
        echo "<time datetime=\"$date\">$date</time>"
        echo "</header>"
        
        get_content "$md_file" | lowdown
        
        echo "</article>"
        
        cat "$TEMPLATES_DIR/footer.html"
    } > "$html_file"
    
    echo "Built: $html_file"
}

build_index() {
    local index_file="$PUBLIC_DIR/index.html"

    {
        sed -e "s/{{TITLE}}/Home/g" \
            -e "s/{{DESCRIPTION}}/Ashwater - A minimal blog about self-hosting, Linux, and tinkering with technology/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            "$TEMPLATES_DIR/header.html"

        echo "<header class=\"hero\">"
        echo "<h1>Ashwater</h1>"
        echo "<p>A minimal blog about self-hosting, Linux, and tinkering with technology.</p>"
        echo "</header>"
        echo "<h2>Posts</h2>"
        echo "<ul class=\"post-list\">"
        
        # Build sortable list: DATE|SLUG|TITLE, then sort and format
        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            echo "${date}|${slug}|${title_html}"
        done | sort -r | while IFS='|' read -r date slug title_html; do
            echo "<li><time datetime=\"$date\">$date</time> <a href=\"/posts/${slug}.html\">$title_html</a></li>"
        done
        
        echo "</ul>"
        
        cat "$TEMPLATES_DIR/footer.html"
    } > "$index_file"
    
    echo "Built: $index_file"
}

build_sitemap() {
    local sitemap_file="$PUBLIC_DIR/sitemap.xml"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        echo "  <url><loc>${protocol}://${DOMAIN}/</loc></url>"
        
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
        
        echo '</urlset>'
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
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">'
        echo '<channel>'
        echo "  <title>Ashwater</title>"
        echo "  <link>${protocol}://${DOMAIN}/</link>"
        echo "  <description>A minimal blog about self-hosting, Linux, and tinkering with technology</description>"
        echo "  <atom:link href=\"${protocol}://${DOMAIN}/feed.xml\" rel=\"self\" type=\"application/rss+xml\"/>"

        # Build sortable list first, then generate items
        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title date description
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            date=$(get_date_with_fallback "$md_file")
            description=$(get_description "$md_file")
            # Escape XML entities
            title=$(printf '%s' "$title" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            description=$(printf '%s' "$description" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            echo "${date}|${slug}|${title}|${description}"
        done | sort -r | while IFS='|' read -r date slug title description; do
            echo "  <item>"
            echo "    <title>$title</title>"
            echo "    <link>${protocol}://${DOMAIN}/posts/${slug}.html</link>"
            echo "    <guid>${protocol}://${DOMAIN}/posts/${slug}.html</guid>"
            echo "    <pubDate>$(date -d "$date" -R 2>/dev/null || echo "$date")</pubDate>"
            echo "    <description>$description</description>"
            echo "  </item>"
        done

        echo '</channel>'
        echo '</rss>'
    } > "$rss_file"

    echo "Built: $rss_file"
}

echo "Building blog..."

for md_file in "$POSTS_DIR"/*.md; do
    [ -f "$md_file" ] || continue
    build_post "$md_file"
done

build_index
build_sitemap
build_robots
build_rss

echo "Done!"
