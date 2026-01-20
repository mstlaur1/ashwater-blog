#!/bin/bash
set -e

BLOG_DIR="/var/www/blog"
POSTS_DIR="$BLOG_DIR/posts"
PUBLIC_DIR="$BLOG_DIR/public"
TEMPLATES_DIR="$BLOG_DIR/templates"
DOMAIN="${BLOG_DOMAIN:-localhost}"

mkdir -p "$PUBLIC_DIR/posts"

parse_frontmatter() {
    local file="$1"
    local key="$2"
    sed -n "/^---$/,/^---$/p" "$file" | grep "^${key}:" | sed "s/^${key}: *//"
}

get_description() {
    local file="$1"
    local desc=$(parse_frontmatter "$file" "description")
    if [ -z "$desc" ]; then
        desc=$(sed '1,/^---$/d' "$file" | grep -v "^$" | head -1 | sed 's/[#*_]//g' | cut -c1-160)
    fi
    echo "$desc"
}

get_slug() {
    local file="$1"
    basename "$file" .md | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'
}

build_post() {
    local md_file="$1"
    local slug=$(get_slug "$md_file")
    local title=$(parse_frontmatter "$md_file" "title")
    local date=$(parse_frontmatter "$md_file" "date")
    local description=$(get_description "$md_file")
    local html_file="$PUBLIC_DIR/posts/${slug}.html"
    
    # Build HTML
    {
        cat "$TEMPLATES_DIR/header.html" | \
            sed "s/{{TITLE}}/$title/" | \
            sed "s/{{DESCRIPTION}}/$description/" | \
            sed "s/{{OG_TYPE}}/article/"
        
        echo "<article>"
        echo "<header>"
        echo "<h1>$title</h1>"
        echo "<time datetime=\"$date\">$date</time>"
        echo "</header>"
        
        # Extract content after frontmatter and convert to HTML
        sed '1,/^---$/d' "$md_file" | lowdown
        
        echo "</article>"
        
        cat "$TEMPLATES_DIR/footer.html"
    } > "$html_file"
    
    echo "Built: $html_file"
}

build_index() {
    local index_file="$PUBLIC_DIR/index.html"
    
    {
        cat "$TEMPLATES_DIR/header.html" | \
            sed "s/{{TITLE}}/Blog/" | \
            sed "s/{{DESCRIPTION}}/A minimal blog served from a Pi Zero 2 W/" | \
            sed "s/{{OG_TYPE}}/website/"
        
        echo "<h1>Posts</h1>"
        echo "<ul class=\"post-list\">"
        
        for md_file in $(ls -r "$POSTS_DIR"/*.md 2>/dev/null); do
            local slug=$(get_slug "$md_file")
            local title=$(parse_frontmatter "$md_file" "title")
            local date=$(parse_frontmatter "$md_file" "date")
            echo "<li><time datetime=\"$date\">$date</time> <a href=\"/posts/${slug}.html\">$title</a></li>"
        done
        
        echo "</ul>"
        
        cat "$TEMPLATES_DIR/footer.html"
    } > "$index_file"
    
    echo "Built: $index_file"
}

build_sitemap() {
    local sitemap_file="$PUBLIC_DIR/sitemap.xml"
    
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "$sitemap_file"
    echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' >> "$sitemap_file"
    echo "  <url><loc>https://${DOMAIN}/</loc></url>" >> "$sitemap_file"
    
    for md_file in "$POSTS_DIR"/*.md; do
        [ -f "$md_file" ] || continue
        local slug=$(get_slug "$md_file")
        local date=$(parse_frontmatter "$md_file" "date")
        echo "  <url>" >> "$sitemap_file"
        echo "    <loc>https://${DOMAIN}/posts/${slug}.html</loc>" >> "$sitemap_file"
        echo "    <lastmod>${date}</lastmod>" >> "$sitemap_file"
        echo "  </url>" >> "$sitemap_file"
    done
    
    echo '</urlset>' >> "$sitemap_file"
    echo "Built: $sitemap_file"
}

build_robots() {
    echo "User-agent: *" > "$PUBLIC_DIR/robots.txt"
    echo "Allow: /" >> "$PUBLIC_DIR/robots.txt"
    echo "" >> "$PUBLIC_DIR/robots.txt"
    echo "Sitemap: https://${DOMAIN}/sitemap.xml" >> "$PUBLIC_DIR/robots.txt"
    echo "Built: $PUBLIC_DIR/robots.txt"
}

echo "Building blog..."

for md_file in "$POSTS_DIR"/*.md; do
    [ -f "$md_file" ] || continue
    build_post "$md_file"
done

build_index
build_sitemap
build_robots

echo "Done!"
