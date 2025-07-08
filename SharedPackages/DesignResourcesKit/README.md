# DesignResourcesKit

## What is it?
`DesignResourcesKit` is a narrowly scoped Swift package containing the implementation of design system elements for iOS and macOS apps. This currently only includes colors and typography. 
See the full documentation here: https://app.asana.com/0/1202500774821704/1204423793264693/f  
  
## Making changes
Any changes to the actual content of this package (e.g. values or names of colors, font sizes or leading etc.) should only be made if the changes are applied across the design system. 
If a design contains typography or colors not in this package, they should either be changed to use something in this package, or those new colors/type styles should be added fully to the design system.
  
Occasionally it may be necessary to add a color that is used in only one place and isn't part of the design system. For these `SingleUseColor` exists. You should think carefully before adding a color here, and question with the designer if it should be part of the design system. 
