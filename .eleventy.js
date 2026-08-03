import { EleventyHtmlBasePlugin } from "@11ty/eleventy";
import Prism from "prismjs";
import loadLanguages from 'prismjs/components/index.js';
import markdownIt from "markdown-it";
import markdownItAnchor from "markdown-it-anchor";
import markdownItGithubAlerts from "markdown-it-github-alerts";
import metagen from 'eleventy-plugin-metagen';
import fs from "fs";
import matter from "gray-matter";
import dirOutputPlugin from "@11ty/eleventy-plugin-directory-output";

export default function (eleventyConfig) {
    eleventyConfig.setQuietMode(true);


    eleventyConfig.addPlugin(EleventyHtmlBasePlugin);
    eleventyConfig.addPlugin(metagen);
    eleventyConfig.addPlugin(dirOutputPlugin, {
		columns: {
			filesize: false,
			benchmark: false,
		},
	});


    eleventyConfig.addPassthroughCopy("assets");
    eleventyConfig.addPassthroughCopy("content",
        {
            filter : ["guides/**", "!guides/**/*.md"],
        }
    )


    const markdownLibrary = markdownIt({
        html: true,
        highlight: (code, lang, attrs) => {
            if (!lang) {
                return code;
            }

            if (!Object.hasOwn(Prism.languages, lang)) {
                loadLanguages([lang]);
            }

            let html = Prism.highlight(code, Prism.languages[lang], lang);
            return `<span data-attrs="${attrs}"></span>${html}`;
        },
    })
        .use(markdownItGithubAlerts)
        .use(markdownItAnchor, {
            permalink: true,
            permalinkClass: "anchor",
            permalinkSymbol: "#",
            permalinkBefore: false
        })

    markdownLibrary.renderer.rules.link_open = function (tokens, idx, options, env, self) {
        const token = tokens[idx];
        const hrefIndex = token.attrIndex("href");

        if (hrefIndex !== -1) {
            let href = token.attrs[hrefIndex][1];

            if (!href.startsWith("http") && !href.startsWith("#") && !href.startsWith("/")) {
                // Fix links to other chapters
                href = "../" + href;
                token.attrs[hrefIndex][1] = href;
                token.attrSet("data-preview", href);
            }
        }

        return self.renderToken(tokens, idx, options);
    };

    eleventyConfig.setLibrary("md", markdownLibrary);

    const getTitleFromFrontMatter = (chapter) => {
        const filePath = `./content/guides/${chapter}.md`;
        if (fs.existsSync(filePath)) {
            const fileContent = fs.readFileSync(filePath, "utf-8");
            const { data } = matter(fileContent);
            return data.title || chapter;
        }
        return chapter;
    }

    eleventyConfig.addShortcode("abstract", function(abstract) {
        this.page.abstract = abstract
        return `<span data-abstract="${abstract}"></span>`;
    });

    const usedIds = new Set();

    const getId = () => {
        let id;
        do {
            id = Math.floor(Math.random() * 1000);
        } while (usedIds.has(id));
        usedIds.add(id);
        return id;
    }

    eleventyConfig.addPairedShortcode("love", (content, width = 800, height = 600, code = false) => {
        const id = getId();

        const formattedContent = content
            .replace(/(\n){2,}/g, '\n')
            .replace(/(\r\n){2,}/g, '\r\n')
            .replace(/(\t){2,}/g, ' ')
            .replace(/( ){2,}/g, ' ')
            .replace(/`/g, '\\`')

        // Note: No indenting to prevent rendering as code block.
        return `${code ? `\`\`\`lua${content}\`\`\`` : ''}
<iframe class="love-embed" id="love-iframe-${id}" src="/assets/love/love-js" width="${width}" height="${height}"></iframe>
<script>
const iframe_${id} = document.getElementById('love-iframe-${id}');
iframe_${id}.addEventListener('load', function() {
iframe_${id}.contentWindow.postMessage({lua: \`love.window.setMode(${width}, ${height}) ${formattedContent}\`}, '*');
});
</script>
        `;
    });

    eleventyConfig.addPairedShortcode("fiddle", function(content, width = 800, height = 600, entranceFile = "main.lua", code = false) {
        const id = getId();

        const url = this.page.url
        const readDir = "../.."+url+"assets/"
        const folderPath = "content"+this.page.url+"assets/"

        const isFile = fileName => {
            return fs.lstatSync(folderPath+fileName).isFile();
        };
        const files = fs.readdirSync(folderPath, {recursive: true})
            .filter(isFile)
            .toString()

        const formattedContent = content
            .replace(/(\n){2,}/g, '\n')
            .replace(/(\r\n){2,}/g, '\r\n')
            .replace(/(\t){2,}/g, ' ')
            .replace(/( ){2,}/g, ' ')
            .replace(/`/g, '\\`')

        // Note: No indenting to prevent rendering as code block.
        return `${code ? `\`\`\`lua${content}\`\`\`` : ''}
<iframe class="love-embed" id="love-iframe-${id}" src="/assets/fiddle" width="${width}" height="${height}"></iframe>

<script>
const iframe_${id} = document.getElementById('love-iframe-${id}');
iframe_${id}.addEventListener('load', function() {
iframe_${id}.contentWindow.postMessage({readDir: "${readDir}", files: "${files}", entranceFile: "${entranceFile}" }) } )
</script>
        `;
    });

    eleventyConfig.addShortcode("api", (name) => {
        const nameWithoutParantheses = name.replace(/\(.*\)$/, "");
        const url = `https://love2d.org/wiki/${nameWithoutParantheses}`;
        return `<a href="${url}" target="_blank"><code>${name}</code></a>`;
    });

    eleventyConfig.addNunjucksFilter("filterByUrl", function (collection, url) {
        const results = collection.filter(item => item.url === url);

        if (results.length === 0) {
            throw new Error(`No item found with URL: ${url}`);
        }

        return results;
    });

    eleventyConfig.addNunjucksFilter("preview", function (content) {
        const match = content.match(/<p>(.*?)<\/p>/);

        // strip tags
        return match ? match[1].replace(/<[^>]*>?/gm, '') : '';
    });

    return {
        pathPrefix: "/",
        dir: {
            input: "content",
            includes: "../templates",
            output: "build",
        },
        markdownTemplateEngine: "njk",
        htmlTemplateEngine: "njk"
    };
}
