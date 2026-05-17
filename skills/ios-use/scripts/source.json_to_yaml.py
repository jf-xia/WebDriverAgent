#!/usr/bin/env python3
"""Convert iOS source JSON to optimized YAML format."""

import json
import yaml
import sys


def clean_rect(rect):
    """Clean rect object: remove x,y if both are 0."""
    if not rect:
        return None
    
    x = rect.get('x', 0)
    y = rect.get('y', 0)
    w = rect.get('width', 0)
    h = rect.get('height', 0)
    
    # All zeros -> remove entirely
    if x == 0 and y == 0 and w == 0 and h == 0:
        return None
    
    # x=0,y=0 -> only keep size
    if x == 0 and y == 0:
        if w > 0 and h > 0:
            return f'{w}x{h}'
        return None
    
    # Keep full rect as compact string
    return f'{x},{y} {w}x{h}'


def has_meaningful_content(node):
    """Check if node has meaningful content beyond just being a container."""
    if not isinstance(node, dict):
        return True
    # Check for type:name combined format (e.g., 'Icon: Calendar')
    for key in node:
        if key in ('children', 'rect', 'traits', 'actions', 'value', 'label'):
            continue
        if key != 'type' and key != 'name':
            # This is a type:name combined key
            return True
    if node.get('type') and node['type'] != 'Other':
        return True
    if node.get('name') or node.get('label'):
        return True
    if node.get('value'):
        return True
    if node.get('traits') and node['traits'].strip():
        return True
    return False


def clean_node(node, parent_actions=None):
    """Recursively clean node, removing null values and empty fields."""
    result = {}
    
    # Type - keep if not 'Other'
    node_type = node.get('type')
    
    # Name/Label - deduplicate
    name = node.get('name')
    label = node.get('label')
    raw_id = node.get('rawIdentifier')
    
    # Use the most descriptive identifier
    identifier = None
    if name and label and name != label:
        identifier = name
        result['label'] = label
    elif name:
        identifier = name
    elif label:
        identifier = label
    elif raw_id:
        identifier = raw_id
    
    # Combine type and name into single key like "Icon: Calendar"
    if node_type and node_type != 'Other' and identifier:
        result[node_type] = identifier
    elif node_type and node_type != 'Other':
        # Keep as type: Window format
        result['type'] = node_type
    elif identifier:
        result['name'] = identifier
    
    # Value
    value = node.get('value')
    if value is not None:
        result['value'] = value
    
    # Traits - keep only if meaningful and not same as type
    traits = node.get('traits')
    if traits and traits.strip():
        # Don't add traits if it's just repeating the type
        if traits != node_type:
            result['traits'] = traits
    
    # Custom actions - only add if different from parent
    custom_actions = node.get('customActions')
    if custom_actions and custom_actions.strip():
        if custom_actions != parent_actions:
            result['actions'] = custom_actions
    
    # Rect - clean
    rect = clean_rect(node.get('rect'))
    if rect:
        result['rect'] = rect
    
    # Current actions for children
    current_actions = node.get('customActions') or parent_actions
    
    # Children - recurse
    children = node.get('children', [])
    if children:
        cleaned_children = []
        for child in children:
            cleaned = clean_node(child, current_actions)
            if cleaned:  # Only add non-empty nodes
                cleaned_children.append(cleaned)
        if cleaned_children:
            result['children'] = cleaned_children
    
    # Remove empty result
    if not result:
        return None
    # If only has empty children, return None
    if list(result.keys()) == ['children'] and not result['children']:
        return None
    return result


def flatten_single_child(node):
    """Flatten nodes that have only one child and no meaningful content."""
    if not isinstance(node, dict):
        return node
    
    # If node has children, process them first
    if 'children' in node:
        node['children'] = [flatten_single_child(c) for c in node['children']]
        node['children'] = [c for c in node['children'] if c is not None]
        
        # If only one child and parent has no meaningful content, merge
        if len(node['children']) == 1 and not has_meaningful_content(node):
            child = node['children'][0]
            # Merge rect if both have it
            if 'rect' in node and 'rect' not in child:
                child['rect'] = node['rect']
            return child
        
        if not node['children']:
            del node['children']
    
    return node if has_meaningful_content(node) or 'children' in node else None


def remove_decoration_nodes(node):
    """Remove decoration nodes (Image with only type and rect)."""
    if not isinstance(node, dict):
        return node
    
    # Check if this is a decoration node
    keys = set(node.keys())
    if keys == {'type', 'rect'} and node.get('type') == 'Image':
        return None
    
    # Process children
    if 'children' in node:
        node['children'] = [remove_decoration_nodes(c) for c in node['children']]
        node['children'] = [c for c in node['children'] if c is not None]
        if not node['children']:
            del node['children']
    
    return node


def main():
    input_file = sys.argv[1] if len(sys.argv) > 1 else 'source.json'
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'source_optimized.yaml'
    remove_decoration = '--remove-decoration' in sys.argv
    
    # Read file with error handling
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f'Error: Input file not found: {input_file}', file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f'Error: Permission denied reading: {input_file}', file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError as e:
        print(f'Error: File encoding error: {e}', file=sys.stderr)
        sys.exit(1)

    # Try strict parsing first, then lenient
    try:
        data = json.loads(content)
    except json.JSONDecodeError as e:
        # print(f'Warning: JSON has control characters at line {e.lineno}, column {e.colno}. Using lenient parsing.', file=sys.stderr)
        try:
            data = json.loads(content, strict=False)
        except json.JSONDecodeError as e2:
            print(f'Error: Failed to parse JSON even with lenient parsing: {e2}', file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f'Unexpected error parsing JSON: {e}', file=sys.stderr)
        sys.exit(1)

    root = data['value']
    
    # Clean the structure
    cleaned = clean_node(root)
    
    # Flatten single-child wrapper nodes
    optimized = flatten_single_child(cleaned)
    
    # Remove decoration nodes if requested
    if remove_decoration:
        optimized = remove_decoration_nodes(optimized)
    
    # Write YAML with compact style
    yaml.add_representer(str, lambda d, s: yaml.representer.SafeRepresenter.represent_str(d, s))
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            yaml.dump(optimized, f, default_flow_style=False, allow_unicode=True, sort_keys=False, width=120)
    except PermissionError:
        print(f'Error: Permission denied writing: {output_file}', file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f'Error writing YAML file: {e}', file=sys.stderr)
        sys.exit(1)
    
    # Stats
    def count_nodes(node):
        if not isinstance(node, dict):
            return 1
        count = 1
        for child in node.get('children', []):
            count += count_nodes(child)
        return count
    
    def count_original(node):
        count = 1
        for child in node.get('children', []):
            count += count_original(child)
        return count
    
    original_count = count_original(root)
    new_count = count_nodes(optimized)
    
    # print(f'Original nodes: {original_count}')
    # print(f'Optimized nodes: {new_count}')
    # print(f'Reduction: {original_count - new_count} nodes ({(1 - new_count/original_count)*100:.1f}%)')
    # print(f'Output: {output_file}')


if __name__ == '__main__':
    main()
