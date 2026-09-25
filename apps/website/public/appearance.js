export const appearances = [
  {id:'liquid-glass',label:'Liquid Glass',path:'M12 3 3 12l9 9 9-9-9-9Zm-9 9h18M12 3l-4 9 4 9 4-9-4-9'},
  {id:'dark',label:'Dark',path:'M20 14.2A8.5 8.5 0 0 1 9.8 4 8.5 8.5 0 1 0 20 14.2Z'},
  {id:'light',label:'Light',path:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm0-6v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5'},
  {id:'space',label:'Space',path:'M16 8c2 2 1.8 5.5-.5 7.8S9.7 18.3 7.7 16.3 6 10.8 8.3 8.5 14 6 16 8ZM5 17C0 22 10 19 16 13s8-13 3-8M19 2v4m-2-2h4'},
];
export const normalizeAppearance=value=>appearances.some(theme=>theme.id===value)?value:'liquid-glass';
export const appearanceIcon=id=>`<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="${appearances.find(theme=>theme.id===normalizeAppearance(id)).path}"/></svg>`;
