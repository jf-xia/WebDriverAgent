#!/usr/bin/env python3
"""Convert iOS source JSON to simple YAML format with only essential fields."""

import json
import yaml
import sys


def clean_rect(rect):
    """Clean rect object."""
    if not rect:
        return None
    
    x = rect.get('x', 0)
    y = rect.get('y', 0)
    w = rect.get('width', 0)
    h = rect.get('height', 0)
    
    # All zeros -> remove
    if x == 0 and y == 0 and w == 0 and h == 0:
        return None
    
    # x=0,y=0 -> only keep size
    if x == 0 and y == 0:
        return f'{w}x{h}' if w > 0 and h > 0 else None
    
    # Full rect
    return f'{x},{y} {w}x{h}'


def clean_node(node):
    """Keep only: type, name, rect, traits, value."""
    result = {}
    
    # Type and Name - combine if both exist
    node_type = node.get('type')
    name = node.get('name') or node.get('label') or node.get('rawIdentifier')
    
    if node_type and node_type != 'Other' and name:
        result[node_type] = name
    elif node_type and node_type != 'Other':
        result['type'] = node_type
    elif name:
        result['name'] = name
    
    # Value
    value = node.get('value')
    if value is not None:
        result['value'] = value
    
    # Traits
    traits = node.get('traits')
    if traits and traits.strip() and traits != node_type:
        result['traits'] = traits
    
    # Rect
    rect = clean_rect(node.get('rect'))
    if rect:
        result['rect'] = rect
    
    # Children - recurse
    children = node.get('children', [])
    if children:
        cleaned_children = []
        for child in children:
            cleaned = clean_node(child)
            if cleaned:
                cleaned_children.append(cleaned)
        if cleaned_children:
            result['children'] = cleaned_children
    
    return result if result else None


def flatten(node):
    """Flatten single-child wrapper nodes and remove rect-only nodes."""
    if not isinstance(node, dict):
        return node
    
    if 'children' in node:
        node['children'] = [flatten(c) for c in node['children']]
        node['children'] = [c for c in node['children'] if c is not None]
        
        # If only one child and parent has no content, merge
        if len(node['children']) == 1:
            has_content = any(k not in ('children', 'rect') for k in node.keys())
            if not has_content:
                child = node['children'][0]
                if 'rect' in node and 'rect' not in child:
                    child['rect'] = node['rect']
                return child
        
        if not node['children']:
            del node['children']
    
    # Remove nodes that only have rect (no type, name, value, traits)
    if isinstance(node, dict) and list(node.keys()) == ['rect']:
        return None
    
    # Remove Window nodes that only have type and rect (no children)
    if isinstance(node, dict) and node.get('type') == 'Window' and 'children' not in node:
        return None
    
    return node


def main():
    input_file = sys.argv[1] if len(sys.argv) > 1 else 'source.json'
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'source_simple.yaml'
    
    with open(input_file, 'r') as f:
        data = json.load(f)
    
    root = data['value']
    cleaned = clean_node(root)
    simplified = flatten(cleaned)
    
    with open(output_file, 'w') as f:
        yaml.dump(simplified, f, default_flow_style=False, allow_unicode=True, sort_keys=False, width=120)
    
    # Stats
    def count_nodes(node):
        if not isinstance(node, dict):
            return 1
        return 1 + sum(count_nodes(c) for c in node.get('children', []))
    
    def count_original(node):
        return 1 + sum(count_original(c) for c in node.get('children', []))
    
    original = count_original(root)
    new = count_nodes(simplified)
    
    print(f'Original: {original} nodes')
    print(f'Simple: {new} nodes')
    print(f'Reduction: {original - new} ({(1 - new/original)*100:.1f}%)')
    print(f'Output: {output_file}')


if __name__ == '__main__':
    main()
