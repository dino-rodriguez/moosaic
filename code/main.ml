open Images;;
open OImages;;
open Info;;
open Color;;

type order = Equal | Less | Greater
type point = Rgb.t
type image = string ref  

module type KDTREE =
sig
  exception EmptyTree
  exception NodeNotFound

  (* The type of an element in the tree *)
  type elt 

  (* What this type actually looks like is left up to the
   * particular KDTREE implementation (i.e. the struct) *)
  type tree
  
  (* Returns an empty tree *)
  val empty : tree

  (* Builds a balanced tree so that a nearest neighbor 
   * search ban be run in optimal time *)
  val build_balanced: elt list -> int -> tree -> tree 

  (* Search a KD tree for the given value and returns
  * the nearest neighbor *) 
  val nearest_neighbor : elt -> tree -> elt

  (* Run invariant checks on the implementation of this KD tree.
   * May raise Assert_failure exception -- examples of these tests 
   * can be found in kdtest.ml *)
  val run_tests : unit -> unit
end


module type COMPARABLE =
sig
  (* the type of element *) 
  type t
  
  (* a method for comparing elements *) 
  val compare : int -> t -> t -> order
  
  (* a method of finding the distance between two elements *)
  val distance : t -> t -> int 
  
  (* a method of finding the distance between an elt and the 
   * corresponding plane of a second elt *) 
  val distance_to_plane : int -> t -> t -> int 
end


(*a module for comparing the actual elements used in the KDTree*)
module PointCompare : COMPARABLE with type t= point*image =
struct
 
  (* the data in our basis of images is represented as a point --
   * the average color vector of the image, and a string that 
   * is a name of that image *) 
  type t = point * image 
  
  (* helper function to compare the r values *) 
  let compareR x y = 
    let (p1,_),(p2,_) = x,y in 
     if p1.r > p2.r then Greater 
     else if p1.r < p2.r then Less 
     else Equal 

  (* helper function to compare the g values *) 
  let compareG x y = 
    let (p1,_),(p2,_) = x,y in 
     if p1.g > p2.g then Greater 
     else if p1.g < p2.g then Less 
     else Equal 
  
  (* helper function to compare the b values *) 
  let compareB x y = 
    let (p1,_),(p2,_) = x,y in 
     if p1.b > p2.b then Greater 
     else if p1.b < p2.b then Less 
     else Equal 
  
  (* compares the two points given a level in the tree 
   * (a dimmension to compare with) *)
  let compare i x y = 
    match (i mod 3) with 
    | 0 -> compareR x y 
    | 1 -> compareG x y 
    | 2 -> compareB x y 
    | _ -> failwith "shouldn't return any other value"
      
 (*calculates the distance between two points*)
  let distance (e1: t) (e2: t) =
    let (p1,_),(p2,_) = e1,e2 in 
    Rgb.square_distance p1 p2 

  (*calculates the distance between a point and the 
   * hyperplane--used to see if other side of tree
   * needs to be traversed as well *)         
  let distance_to_plane (c: int) e1 e2 = 
    match (c mod 3) with 
    | 0 -> let (p,x) = e2 in distance e1 ({r = p.r; g = 0; b = 0},x) 
    | 1 -> let (p,x) = e2 in distance e1 ({r = 0; g = p.g; b = 0},x)
    | 2 -> let (p,x) = e2 in distance e1 ({r = 0; g = 0; b = p.b},x)  
    | _ -> failwith "shouldn't be any other value!" 
 
end


(* Actual KDTree module *)
module KDTree(C : COMPARABLE) : KDTREE with type elt = C.t =
struct
  exception EmptyTree
  exception NodeNotFound

  (* Grab the type of the tree from the module C that's passed in *)
  type elt = C.t 

  (* One possible type for a tree *)
  type tree = Leaf | Branch of tree * elt * tree

  (* Representation of the empty tree *)
  let empty = Leaf
  
 (* function for determining  max of an int to help with
  * is_balanced function for testing *)
  let max x y = if x > y then x else y 

  
  (* function to determine max depth of tree *)
  let max_depth (t: tree) : int =
    let rec max_dep (m: int) (lst: (tree*int) list) = 
    (* m is the max, and the int in the tree*int list
     * is the current depth. we compare the current 
     * max to the current depth and continue traversing
     * through adding 1 to the current depth of each 
     * tree *) 
      match lst with 
      | [] -> m 
      | (Leaf,c)::tl -> max_dep (max m c) tl 
      | (Branch(l,lst,r), c)::tl -> max_dep (max m c) ((l, c+1)::(r,c+1)::tl)
    in max_dep 0 [(t,0)]

  (* funtion to determine min depth of a tree *)
  let min_depth (t: tree) : int = 
    let rec min_dep (m: int) (lst: (tree*int) list) = 
    match lst with 
    | [] -> m 
    | (Leaf,c) :: tl -> if c < m then min_dep c tl else min_dep m tl 
    | (Branch(l,lst,r),c)::tl -> min_dep m ((l, c+1)::(r,c+1)::tl)
  in min_dep (max_depth t) [(t,0)]


  (* function to check if tree is balanced - checks to see if 
   * min_depth and max_depth are one apart or equal. helps 
   * for testing purposes *)
  let is_balanced (t: tree) : bool = 
    if abs(max_depth t - min_depth t) <= 1 then true
    else false 

  (* function that will help sort by designated dimmension -- 
   * returns 0, 1, or -1 so it can be used with the List.sort 
   * function *)
  let sort (x: elt) (y: elt) (c: int): int = 
    match C.compare c x y with 
    | Equal -> 0 
    | Greater -> 1 
    | Less -> -1 

  (* sorts all the elements in the tree by given dimmension *)
  let sort_list (lst: elt list) (c: int) : elt list = 
    List.sort (fun x y -> sort x y c) lst 
  
  (*find what index the median of a sorted list is at*) 
  let index (lst: elt list) : int =
      let length = List.length lst in 
        if length mod 2 = 0 then 
            length / 2
        else (length - 1) / 2 
    
  (* finds the median of a sorted list *)
  let find_median (lst: elt list) : elt  =  
       List.nth lst (index lst)
      
  
  (* takes in a list, and divides it in half at the median. 
   * used for the build_balanced function so that the 
   * tree is built smart *) 
  let rec divide_lists lst left right middle c median = 
    match lst with 
    | [] -> (left, right) 
    | hd :: tl -> if c < median then 
                    divide_lists tl (hd :: left) right middle (c+1) median 
                  else if c > median then 
                    divide_lists tl left (hd :: right) middle (c+1) median
                  else 
                    divide_lists tl left right (hd :: middle) (c+1) median 
                    
  (* builds a balanced tree -- elements are sorted by their first 
   * component, the median is used as the root of the tree, and then
   * the remaining elements are recursively subdivided into children
   * of the root node *)
  let rec build_balanced (lst: elt list) (c: int) (t: tree) : tree = 
    match lst with 
    | [] -> t
    | _ -> let sorted_lst = sort_list lst c in 
           let new_node = find_median sorted_lst in 
           let (left_list, right_list) = 
            divide_lists (sorted_lst) [] [] [] 0 (index lst) 
           in Branch((build_balanced left_list (c+1) empty), new_node,
            (build_balanced right_list (c+1) empty))
           
       
  (* Nearest neighbor function for KD trees--takes in a type elt and a tree and 
  * returns the elt closest to the given elt in the tree *)
  let nearest_neighbor (x : elt) (t : tree) : elt  =
    let rec traverse (o: elt) (current_best: elt) (k: tree) (d: int) (c: int) =
        match k with 
        | Leaf -> current_best
        | Branch (l, hd, r) -> 
            let (current_best, d) = if C.distance hd o < d then 
                (hd, C.distance hd o) else (current_best, d) in
            match C.compare c o hd with
                | Less -> 
                    let current_best = traverse o current_best l d (c+1) in
                    if C.distance_to_plane c o hd <= 
                        (C.distance current_best o) then
                    traverse o current_best r d (c+1) else current_best
                | Greater | Equal -> 
                    let current_best = traverse o current_best r d (c+1) in
                    if C.distance_to_plane c o hd <= 
                        (C.distance current_best o) then 
                    traverse o current_best l d (c+1) else current_best in 
  match t with 
  | Leaf -> failwith "there are no nodes in this tree"
  | Branch(_, hd, _) -> traverse x hd t (C.distance hd x) 0 
            
  (* because of abstraction, these tests weren't implemented in this file. 
   * in the file kdtest.ml, you can run these tests and check for 
   * assert failures *) 
  let test_balance () = 
    ()
    
  let test_nearest_neighbor () =
    ()
 
  let test_insert ()  = 
    ()

  let run_tests () =
    ()

end

module PointTree = KDTree(PointCompare);;

(* The Pixels module, in which we do all our pixel and image 
 * manipulation *)
module type PIXELS = 
    sig 
      (* finds the average color of an image and returns it and the 
       * image itself  *)
      val average_color : bytes ref -> rgb24 option -> point * bytes ref
      
      (* finds the avg color of all the images in the library and 
       * returns a list of the average colors and the images *)
      val avg_color_images : (point * bytes ref) list 
      
      (* crops and resizes and image *) 
      val crop_resize : bytes ref -> int -> unit 
      
      (* crops and resizes all the images in the library to the 
       * designated size indicated by the user -- we realize 
       * that this is inefficient, but seeing as it was impossible
       * to manipulate the image once it was in the tree, it made 
       * the most sense, especially since we only had around 300
       * images in the library, and most of the time we use 
       * way more than 300 images in a picture *)
      val crop_resize_all : int -> unit 
      
      (* divides up the image into tiles based on the users input
       * for minimum number of tiles in a moosaic. returns the 
       * dimmensions that each tile needs to be *) 
      val gridder : int -> bytes ref -> int 
      
      (* swaps in every tile in the tree based on the average
       * color *) 
      val blitz : PointTree.tree -> bytes ref -> int -> unit 
    end


module Pixels : PIXELS = 
    struct 
    
    (* Iterates through an rgb24 bitmap image and calculates the average
     * color of the image by summing the red, green, and blue of each
     * pixel respectively, and then calculating the average RGB.
     * Returns the a tuple of the avg, color and filepath. In the case
     * that a tile is used, the file path will be empty *)
    let average_color (filepath : string ref) (tile : rgb24 option) :
    (Rgb.t * string ref) = 
      (* Used for "swapping" memory from heap if there is overflow. 
       * Integrated into camlimages library, but buggy so it is disabled. *)
      Bitmap.maximum_live := 0;
      let img = 
      (match tile with 
       | None -> let file = !filepath in (OImages.rgb24 (OImages.load file []))
       | Some t ->  t) in 
      let width = img#width in 
      let height = img#height in 
      let pixels = width * height in 
      let color = ref {Rgb.r= 0; g = 0; b = 0;}  in
      for i = 0 to width - 1 do
         for j = 0 to height - 1 do
           color := Rgb.plus (!color) (img#get i j)
               done;
           done; 
      let new_color = {Rgb.r = ((!color).r / pixels); g = 
          ((!color).g / pixels); b = ((!color).b / pixels);} in
      (new_color, filepath) 
    ;; 

    (* Calculates the average color of all the images in the "outphotos" folder
     * These are the images that will be used as tiles for the photomosaic. *)
    let avg_color_images = 
      let info = Array.to_list (Sys.readdir "outphotos") in
      let color_path = List.map (fun a -> 
        (average_color (ref ("outphotos/" ^ a)) None)) info in
       color_path
    ;;

    (* Crops a image to a square by cropping evenly from both sides, and 
     * then resizes it to the inputted dimensions (s). Does this to
     * maintain aspect ratio for square monosized tiles. *)
    let crop_resize (filepath : string ref) (s : int) : unit =
      Bitmap.maximum_live := 0; 
      let file = !filepath in 
      let outfile = "out" ^ file in
      let fmt, _ = Images.file_format file in
      let img = OImages.load file [] in
      if img#image_class <> ClassRgb24 then 
        Sys.remove file
      else 
     (let img = OImages.rgb24 img in 
        (* Helper function to crop image evenly from both sides, whether 
         * it be cropping height or width. *)
        let square_crop i (w : int) (h : int) = 
          let diff = abs (w - h) in
            if w > h then i#sub (diff / 2) 0 (w - diff) h
            else i#sub 0 (diff / 2) w (h - diff) in
      let cropped = square_crop img img#width img#height in
      let new_img = cropped#resize None s s in
        new_img#save outfile (Some fmt) [Save_Quality 95])
    ;;

    (* Crops and resizes all images in the "photos" folder into monosized 
     * tiles of the given dimensions (s). Place the copies into an "outphotos"
     * folder. *)
    let crop_resize_all (s : int) = 
      let paths = Array.to_list (Sys.readdir "photos") in
        List.iter (fun x -> crop_resize (ref ("photos/" ^ x)) s) paths
    ;;

    (* Takes in the minimum number of tiles the user wants and the base image,
     * and returns the tile dimensions (square). Also crops the base image
     * to perfectly fit the calculated tile dimensions. The tile dimensions 
     * are calculated from an algorithm the uses sqrt n for the base of its 
     * calculations. n being the minimum number of tiles the user wants. *)
    let gridder (n : int) (filepath : string ref) : int = 
      Bitmap.maximum_live := 0; 
      let file = !filepath in 
      let outfile = "out" ^ file in
      let fmt, _ = Images.file_format file in
      let img = OImages.rgb24 (OImages.load file []) in
        let small_side = if img#width > img#height then img#height 
                         else img#width in
        let tile_side = truncate ((float small_side) /. (sqrt (float n))) in 
        let new_width = tile_side * (img#width / tile_side) in
        let new_height = tile_side * (img#height / tile_side) in  
        let lost_pixels_width = img#width - new_width in
        let lost_pixels_height = img#height - new_height in
        let bmp_cropped = img#sub (lost_pixels_width / 2) 
          (lost_pixels_height / 2) (img#width - lost_pixels_width) 
          (img#height - lost_pixels_height) in
            bmp_cropped#save outfile (Some fmt) [Save_Quality 95] ; 
            tile_side
    ;;

    (* Selects an image stored in the kd-tree using the nearest neighbor search 
     * to find the image with the nearest avg RGB to the current tile, bitblits
     * the image onto the tile, and moves on. Does this for every tile in the 
     * base image. *)
    let blitz (img_tree : PointTree.tree) (base_path : string ref) (s : int) : unit = 
      Bitmap.maximum_live := 0; 
      let file = !base_path in 
      let outfile = "out" ^ file in
      let fmt, _ = Images.file_format file in
      let img = OImages.rgb24 (OImages.load file []) in
      (* Does everything stated above *)
        let rec swapper s img_tree x y =
          let select_image (t: PointTree.tree) (elt: (PointTree.elt)) = 
            let (_, path) = PointTree.nearest_neighbor elt t in 
            let file = !path in
            let img = (OImages.rgb24 (OImages.load file [])) in img in
          if x <> img#width then 
          let lit = select_image img_tree (average_color (ref "") (Some 
            (img#sub x y s s))) in
              (lit#blit 0 0 img x y s s; swapper s img_tree (x + s) y)
          else if y <> (img#height - s) then swapper s img_tree 0 (y + s)
          else () in
        swapper s img_tree 0 0 ;
        img#save outfile (Some fmt) [Save_Quality 95]  
    ;;  
end


(* the final function the user uses to create the moosaic. num 
 * is the minimum number of tiles the user wants their moosaic
 * to be comprised of, and str is the string name of the image
 * they want their moosaic to resemble *) 
let masterpiece (num: int) (str: string) = 
  let file = !(ref str) in 
  let img = OImages.rgb24 (OImages.load file []) in
  (* checks to make sure the number is valid *) 
  if (img#height * img#width) / 10 < num || num < 1 
        then Printf.printf "Invalid number of images!" 
  else let size = Pixels.gridder num (ref str) in 
    Pixels.crop_resize_all size; 
    let tree = PointTree.build_balanced Pixels.avg_color_images 0 
                PointTree.empty in 
      Pixels.blitz tree (ref ("out"^str)) size
;;
