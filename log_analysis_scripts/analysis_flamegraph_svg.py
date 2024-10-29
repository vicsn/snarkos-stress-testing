import re
import argparse

def parse_svg_titles_janky(svg_content):
    # Find all <title> tags and their content
    title_pattern = re.compile(r'<title>\s*(.*?)\s*</title>', re.DOTALL)
    # title_pattern = re.compile(r'<title>(.*?)</title>', re.DOTALL)
    titles = title_pattern.findall(svg_content)

    results = []

    # Look for specific function and capture the next <title>
    for i, title in enumerate(titles[:-1]):  # Avoid last index to prevent out of range error
        if "call_once" in title or "call_mut" in title or "try_fold":
            # Get the next title content
            next_title = titles[i + 1]
            # Extract only the function name portion before any samples/percentages
            match = re.match(r"([\w:$<>]+)", next_title)
            if match:
                results.append(match.group(1))

    # Parse results into tuples of (function_name, count) and sort by count
    results = [(f, results.count(f)) for f in set(results)]
    results = sorted(results, key=lambda x: x[1], reverse=True)

    return results

def main():
    # Use argparse to read the SVG file path
    parser = argparse.ArgumentParser(description="Parse Flamegraph SVG for specific function names")
    parser.add_argument("svg_file", type=argparse.FileType("r"), help="Path to Flamegraph SVG file")
    args = parser.parse_args()
    svg_content = args.svg_file.read()

    # Call the function and print results
    results = parse_svg_titles_janky(svg_content)
    for result in results:
        print(result)

def test():
    # Example SVG input
    svg_content = """
    <svg xmlns="http://www.w3.org/2000/svg">
        <g><title>core::ops::function::FnOnce::call_once{{vtable.shim}} (7,492,836,461 samples, 2.25%)</title>
        <rect x="0.8805%" y="613" width="2.2479%" height="15" fill="rgb(254,30,23)" fg:x="2935052336" fg:w="7492836461"/>
        <text x="1.1305%" y="623.50">c..</text></g>
        <g><title>snarkvm_algorithms::snark::varuna::ahp::selectors::apply_randomized_selector (65,859,220 samples, 0.02%)</title>
    </svg>
    """
    # Call the function and print results
    print(parse_svg_titles_janky(svg_content))

if __name__ == "__main__":
    main()