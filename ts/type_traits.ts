export type enable_if<b extends boolean, T> = b extends true ? {type: T} : {type: number};
export type enable_if_t<b extends boolean, T> = enable_if<b, T>["type"]
export type extend<T, U> = T extends U ? true : false;
export type not<T> = T extends true ? false : true;