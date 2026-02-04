#!/bin/bash
set -eu

export LC_ALL=C.UTF-8

BLOG_DIR="/var/www/blog"
POSTS_DIR="$BLOG_DIR/posts"
PI_STORIES_DIR="$BLOG_DIR/pi-stories"
PAGES_DIR="$BLOG_DIR/pages"
PUBLIC_DIR="$BLOG_DIR/public"
TEMPLATES_DIR="$BLOG_DIR/templates"
DOMAIN="${BLOG_DOMAIN:-localhost}"
# Tag configuration
# Auto-discover tags from posts
discover_tags() {
    for md_file in "$POSTS_DIR"/*.md; do
        [ -f "$md_file" ] || continue
        grep -m1 "^tag:" "$md_file" | cut -d: -f2 | tr -d " "
    done | sort -u
}
VALID_TAGS=()

generate_tag_nav() {
    local nav="Browse by: "
    local first=true
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        local display
        display=$(echo "$tag" | sed "s/-/ /g; s/\\b./\\u&/g")
        [ "$first" = true ] && first=false || nav+=" · "
        nav+="<a href=\"/tags/${tag}/\">${display}</a>"
    done < <(discover_tags)
    echo "$nav"
}

get_tag() {
    local file="$1"
    parse_frontmatter "$file" "tag"
}

get_tag_html() {
    local tag="$1"
    if [ -n "$tag" ]; then
        printf "<a href=\"/tags/%s/\" class=\"tag tag-%s\">%s</a>" "$tag" "$tag" "$tag"
    fi
}


# Preflight check
if ! command -v lowdown &> /dev/null; then
    echo "Error: lowdown is required but not installed" >&2
    exit 1
fi

mkdir -p "$PUBLIC_DIR/posts"
mkdir -p "$PUBLIC_DIR/pi-stories"
mkdir -p "$PUBLIC_DIR/tags"

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

        # BlogPosting JSON-LD
        local title_json desc_json
        title_json=$(printf "%s" "$title_html" | sed 's/"/\\"/g')
        desc_json=$(printf "%s" "$desc_html" | sed 's/"/\\"/g')
        echo "<script type=\"application/ld+json\">"
        echo "{\"@context\":\"https://schema.org\",\"@type\":\"BlogPosting\","
        echo "\"headline\":\"$title_json\","
        echo "\"datePublished\":\"$date\","
        echo "\"description\":\"$desc_json\","
        echo "\"url\":\"$canonical\","
        echo "\"author\":{\"@type\":\"Person\",\"name\":\"Mikhail St-Laurent\"}}"
        echo "</script>"

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

# New build_index function that reads from pages/home.md

build_index() {
    local index_file="$PUBLIC_DIR/index.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    # Read from home.md if it exists, otherwise use defaults
    local home_title="Ashwater"
    local home_tagline="Projects, planes, and parenthood."
    local home_description="Projects, planes, and parenthood. A tinkerer's journal from the Laurentians."
    local home_content=""

    if [ -f "$PAGES_DIR/home.md" ]; then
        local parsed_title parsed_tagline
        parsed_title=$(parse_frontmatter "$PAGES_DIR/home.md" "title")
        parsed_tagline=$(parse_frontmatter "$PAGES_DIR/home.md" "tagline")
        [ -n "$parsed_title" ] && home_title="$parsed_title"
        [ -n "$parsed_tagline" ] && home_tagline="$parsed_tagline"
        home_description="$home_tagline A tinkerer's journal from the Laurentians."
        home_content=$(get_content "$PAGES_DIR/home.md" | lowdown)
    fi

    # Fallback intro if home.md has no content
    if [ -z "$home_content" ]; then
        home_content="<p>Welcome. I'm Mikhail—father, airline pilot, and habitual tinkerer.</p>
<p>This site is my journal: notes on self-hosting, aviation, fatherhood, and whatever else I'm building or breaking. It runs on a Raspberry Pi Zero 2 W drawing half a watt, because in an age of bloated frameworks and infinite cloud compute, there's something satisfying about creative constraints.</p>
<p>No tracking. No JavaScript. Just words, served from a shelf in the Laurentians.</p>"
    fi

    local title_sed tagline_sed desc_sed
    title_sed=$(sed_escape "$home_title")
    tagline_sed=$(sed_escape "$home_tagline")
    desc_sed=$(sed_escape "$home_description")

    {
        sed -e "s/{{TITLE}}/Home/g" \
            -e "s/{{DESCRIPTION}}/$desc_sed/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/|g" \
            "$TEMPLATES_DIR/header.html"

        # WebSite JSON-LD
        echo "<script type=\"application/ld+json\">"
        echo "{\"@context\":\"https://schema.org\",\"@type\":\"WebSite\","
        echo "\"name\":\"$title_sed\","
        echo "\"url\":\"${protocol}://${DOMAIN}/\","
        echo "\"author\":{\"@type\":\"Person\",\"name\":\"Mikhail St-Laurent\"}}"
        echo "</script>"

        echo "<header class=\"hero\">"
        echo "<h1>$title_sed</h1>"
        echo "<p class=\"tagline\">$tagline_sed</p>"
        echo "</header>"

        echo "<section class=\"intro\">"
        echo "$home_content"
        echo "</section>"

        echo "<h2>Recent Posts</h2>"
        echo "<ul class=\"post-list\">"

        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date tag
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            tag=$(get_tag "$md_file")
            echo "${date}|${slug}|${title_html}|${tag}"
        done | sort -r | head -5 | while IFS="|" read -r date slug title_html tag; do
            local tag_html=""
            [ -n "$tag" ] && tag_html=" <a href=\"/tags/${tag}/\" class=\"tag tag-${tag}\">${tag}</a>"
            echo "<li><time datetime=\"$date\">$date</time> ${tag_html}<a href=\"/posts/${slug}.html\">$title_html</a></li>"
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

build_about() {
    local about_file="$PUBLIC_DIR/about.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"

    if [ ! -f "$PAGES_DIR/about.md" ]; then
        echo "Warning: pages/about.md not found, skipping about page"
        return
    fi

    local about_title about_description about_content
    about_title=$(parse_frontmatter "$PAGES_DIR/about.md" "title")
    [ -z "$about_title" ] && about_title="About"
    about_description=$(parse_frontmatter "$PAGES_DIR/about.md" "description")
    [ -z "$about_description" ] && about_description="About the author"
    about_content=$(get_content "$PAGES_DIR/about.md" | lowdown)

    local title_sed desc_sed
    title_sed=$(sed_escape "$about_title")
    desc_sed=$(sed_escape "$about_description")

    {
        sed -e "s/{{TITLE}}/$title_sed/g" \
            -e "s/{{DESCRIPTION}}/$desc_sed/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/about.html|g" \
            "$TEMPLATES_DIR/header.html"

        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\"><a href=\"/\">~</a><span class=\"sep\">/</span><span>about</span></nav>"
        echo "<article>"
        echo "<h1>$about_title</h1>"
        echo "$about_content"
        echo "</article>"

        output_footer
    } > "$about_file"

    echo "Built: $about_file"
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

        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\"><a href=\"/\">~</a><span class=\"sep\">/</span><span>posts</span></nav>"
        echo "<header class=\"hero\">"
        echo "<h1>Posts</h1>"
        echo "<p>Everything I've written, newest first.</p>"
        echo "</header>"
        echo "<nav class=\"tag-nav\">$(generate_tag_nav)</nav>"
        echo "<ul class=\"post-list\">"

        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local slug title title_html date tag
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            title_html=$(html_escape "$title" | strip_newlines)
            date=$(get_date_with_fallback "$md_file")
            tag=$(get_tag "$md_file")
            echo "${date}|${slug}|${title_html}|${tag}"
        done | sort -r | while IFS="|" read -r date slug title_html tag; do
            local tag_html=""
            [ -n "$tag" ] && tag_html=" <a href=\"/tags/${tag}/\" class=\"tag tag-${tag}\">${tag}</a>"
            echo "<li><time datetime=\"$date\">$date</time> ${tag_html}<a href=\"/posts/${slug}.html\">$title_html</a></li>"
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

        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\"><a href=\"/\">~</a><span class=\"sep\">/</span><span>pi-stories</span></nav>"
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
Disallow: /honeypot/
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


build_tag_index() {
    local tag="$1"
    local tag_dir="$PUBLIC_DIR/tags/$tag"
    local index_file="$tag_dir/index.html"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    
    mkdir -p "$tag_dir"
    
    local tag_display
    tag_display=$(echo "$tag" | sed "s/-/ /g; s/\b./\u&/g")
    
    {
        sed -e "s/{{TITLE}}/$tag_display/g" \
            -e "s/{{DESCRIPTION}}/Posts about $tag_display/g" \
            -e "s/{{OG_TYPE}}/website/g" \
            -e "s|{{CANONICAL}}|${protocol}://${DOMAIN}/tags/${tag}/|g" \
            "$TEMPLATES_DIR/header.html"
        
        echo "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\"><a href=\"/\">~</a><span class=\"sep\">/</span><a href=\"/posts/\">posts</a><span class=\"sep\">/</span><span>$tag_display</span></nav>"
        echo "<header class=\"hero\">"
        echo "<h1>$tag_display</h1>"
        echo "<p>Posts tagged with <span class=\"tag tag-${tag}\">${tag}</span></p>"
        echo "<p class=\"rss-link\"><a href=\"/tags/${tag}/feed.xml\">RSS Feed</a></p>"
        echo "</header>"
        echo "<ul class=\"post-list\">"
        
        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local post_tag slug title title_html date
            post_tag=$(get_tag "$md_file")
            [ "$post_tag" != "$tag" ] && continue
            
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
        echo "<p class=\"more-link\"><a href=\"/posts/\">&larr; All posts</a></p>"
        
        output_footer
    } > "$index_file"
    
    echo "Built: $index_file"
}

build_tag_rss() {
    local tag="$1"
    local rss_file="$PUBLIC_DIR/tags/$tag/feed.xml"
    local protocol="https"
    [ "$DOMAIN" = "localhost" ] && protocol="http"
    
    local tag_display
    tag_display=$(echo "$tag" | sed "s/-/ /g; s/\b./\u&/g")
    
    {
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        echo "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">"
        echo "<channel>"
        echo "  <title>Ashwater - $tag_display</title>"
        echo "  <link>${protocol}://${DOMAIN}/tags/${tag}/</link>"
        echo "  <description>Posts about $tag_display from Ashwater</description>"
        echo "  <atom:link href=\"${protocol}://${DOMAIN}/tags/${tag}/feed.xml\" rel=\"self\" type=\"application/rss+xml\"/>"
        
        for md_file in "$POSTS_DIR"/*.md; do
            [ -f "$md_file" ] || continue
            local post_tag slug title date description
            post_tag=$(get_tag "$md_file")
            [ "$post_tag" != "$tag" ] && continue
            
            slug=$(get_slug "$md_file")
            title=$(parse_frontmatter "$md_file" "title")
            [ -z "$title" ] && title="$slug"
            date=$(get_date_with_fallback "$md_file")
            description=$(get_description "$md_file")
            title=$(printf "%s" "$title" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            description=$(printf "%s" "$description" | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g")
            echo "${date}|${slug}|${title}|${description}"
        done | sort -r | while IFS="|" read -r date slug title description; do
            [ -z "$date" ] && continue
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

build_all_tags() {
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        build_tag_index "$tag"
        build_tag_rss "$tag"
    done < <(discover_tags)
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
        grep -q "^draft: true" "$md_file" && continue
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
build_about
build_posts_index
build_pi_stories_index
build_sitemap
build_robots
build_rss
build_stories_rss

build_all_tags

echo "Done!"
