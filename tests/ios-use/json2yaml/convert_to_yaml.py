#!/usr/bin/env python3
"""Convert iOS source JSON to simplified YAML format."""

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
            return {'w': w, 'h': h}
        return None
    
    # Keep full rect
    return {'x': x, 'y': y, 'w': w, 'h': h}


def clean_node(node):
    """Recursively clean node, removing null values and empty fields."""
    result = {}
    
    # Type - keep if not 'Other'
    node_type = node.get('type')
    if node_type and node_type != 'Other':
        result['type'] = node_type
    
    # Name/Label - deduplicate
    name = node.get('name')
    label = node.get('label')
    raw_id = node.get('rawIdentifier')
    
    # Use the most descriptive identifier
    if name and label and name != label:
        result['name'] = name
        result['label'] = label
    elif name:
        result['name'] = name
    elif label:
        result['name'] = label
    elif raw_id:
        result['name'] = raw_id
    
    # Value
    value = node.get('value')
    if value is not None:
        result['value'] = value
    
    # Traits - keep only if meaningful
    traits = node.get('traits')
    if traits and traits.strip():
        result['traits'] = traits
    
    # Custom actions - keep only if meaningful
    custom_actions = node.get('customActions')
    if custom_actions and custom_actions.strip():
        result['actions'] = custom_actions
    
    # Rect - clean
    rect = clean_rect(node.get('rect'))
    if rect:
        result['rect'] = rect
    
    # Children - recurse
    children = node.get('children', [])
    if children:
        cleaned_children = []
        for child in children:
            cleaned = clean_node(child)
            if cleaned:  # Only add non-empty nodes
                cleaned_children.append(cleaned)
        if cleaned_children:
            result['children'] = cleaned_children
    
    return result if result else None


def simplify_structure(node, depth=0, max_depth=None):
    """Further simplify by removing unnecessary wrapper nodes."""
    if max_depth and depth >= max_depth:
        return node
    
    # If a node has only one child and no meaningful content, merge
    if 'children' in node and len(node['children']) == 1:
        child = node['children'][0]
        # If parent has no name/type/value, just return child
        if not node.get('name') and not node.get('type') and not node.get('value'):
            return simplify_structure(child, depth, max_depth)
    
    # Recursively simplify children
    if 'children' in node:
        node['children'] = [simplify_structure(c, depth + 1, max_depth) for c in node['children']]
        # Remove None children
        node['children'] = [c for c in node['children'] if c is not None]
        if not node['children']:
            del node['children']
    
    return node


def main():
    input_file = sys.argv[1] if len(sys.argv) > 1 else 'source.json'
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'source.yaml'
    
    with open(input_file, 'r') as f:
        data = json.load(f)
    
    root = data['value']
    
    # Clean the structure
    cleaned = clean_node(root)
    
    # Simplify wrapper nodes
    simplified = simplify_structure(cleaned)
    
    # Write YAML
    with open(output_file, 'w') as f:
        yaml.dump(simplified, f, default_flow_style=False, allow_unicode=True, sort_keys=False, width=120)
    
    # Stats
    def count_nodes(node):
        count = 1
        for child in node.get('children', []):
            count += count_nodes(child)
        return count
    
    original_count = count_nodes(root)
    new_count = count_nodes(simplified)
    
    print(f'Original nodes: {original_count}')
    print(f'Cleaned nodes: {new_count}')
    print(f'Reduction: {original_count - new_count} nodes ({(1 - new_count/original_count)*100:.1f}%)')
    print(f'Output: {output_file}')


if __name__ == '__main__':
    main()
